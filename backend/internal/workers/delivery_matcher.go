package workers

import (
	"context"
	"fmt"
	"log"
	"math"
	"time"

	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/internal/websocket"
	"github.com/chizze/backend/pkg/appwrite"
	redispkg "github.com/chizze/backend/pkg/redis"
	"github.com/redis/go-redis/v9"
)

// DeliveryMatcher periodically checks for orders that are ready but have no delivery partner assigned.
// It finds available riders near the restaurant and creates delivery requests.
type DeliveryMatcher struct {
	awService   *services.AppwriteService
	geoService  *services.GeoService
	redisClient *redispkg.Client
	hub         *websocket.Hub
	broadcaster *websocket.EventBroadcaster
	interval    time.Duration
}

func NewDeliveryMatcher(
	awService *services.AppwriteService,
	geoService *services.GeoService,
	redisClient *redispkg.Client,
	hub *websocket.Hub,
	interval time.Duration,
) *DeliveryMatcher {
	return &DeliveryMatcher{
		awService:   awService,
		geoService:  geoService,
		redisClient: redisClient,
		hub:         hub,
		broadcaster: websocket.NewEventBroadcaster(hub),
		interval:    interval,
	}
}

func (w *DeliveryMatcher) Start(ctx context.Context) {
	ticker := time.NewTicker(w.interval)
	defer ticker.Stop()

	log.Println("[worker] DeliveryMatcher started (interval: " + w.interval.String() + ")")

	for {
		select {
		case <-ctx.Done():
			log.Println("[worker] DeliveryMatcher stopped")
			return
		case <-ticker.C:
			w.process(ctx)
		}
	}
}

func (w *DeliveryMatcher) process(ctx context.Context) {
	// 1. Find orders with status "ready" and no delivery_partner_id (null or empty)
	queriesNull := []string{
		appwrite.QueryEqual("status", "ready"),
		appwrite.QueryIsNull("delivery_partner_id"),
	}

	resultNull, err := w.awService.ListOrders(queriesNull)
	if err != nil {
		log.Printf("[worker] DeliveryMatcher error listing orders (null): %v", err)
		return
	}

	queriesEmpty := []string{
		appwrite.QueryEqual("status", "ready"),
		appwrite.QueryEqual("delivery_partner_id", ""),
	}
	resultEmpty, errE := w.awService.ListOrders(queriesEmpty)
	if errE != nil {
		log.Printf("[worker] DeliveryMatcher error listing orders (empty): %v", errE)
	}

	// Merge and deduplicate
	seen := make(map[string]bool)
	var docs []map[string]interface{}
	if resultNull != nil {
		for _, d := range resultNull.Documents {
			id, _ := d["$id"].(string)
			if !seen[id] {
				seen[id] = true
				docs = append(docs, d)
			}
		}
	}
	if resultEmpty != nil {
		for _, d := range resultEmpty.Documents {
			id, _ := d["$id"].(string)
			if !seen[id] {
				seen[id] = true
				docs = append(docs, d)
			}
		}
	}

	if len(docs) == 0 {
		return
	}

	for _, doc := range docs {
		orderID, _ := doc["$id"].(string)
		restaurantID, _ := doc["restaurant_id"].(string)
		customerID, _ := doc["customer_id"].(string)

		// 2. Check Redis lock to prevent re-matching an already-pending order
		pendingKey := "pending_delivery:" + orderID
		acquired, lockErr := w.redisClient.SetNX(ctx, pendingKey, "1", 60*time.Second)
		if lockErr != nil || !acquired {
			// Already pending assignment — skip
			continue
		}

		// 3. Get restaurant details
		restaurant, err := w.awService.GetRestaurant(restaurantID)
		if err != nil {
			log.Printf("[worker] DeliveryMatcher: can't get restaurant %s: %v", restaurantID, err)
			_ = w.redisClient.Del(ctx, pendingKey)
			continue
		}

		restLng, _ := restaurant["longitude"].(float64)
		restLat, _ := restaurant["latitude"].(float64)
		restName, _ := restaurant["name"].(string)
		restCuisine, _ := restaurant["cuisine_type"].(string)
		restAddr, _ := restaurant["address"].(string)

		// 4. Find online riders within 5 km via Redis geo index
		riderIDs, err := w.findNearbyRiders(ctx, restLat, restLng, 5.0)
		if err != nil || len(riderIDs) == 0 {
			log.Printf("[worker] DeliveryMatcher: no riders near restaurant %s for order %s", restaurantID, orderID)
			_ = w.redisClient.Del(ctx, pendingKey)
			continue
		}

		// 5. Get customer delivery address info
		addrID, _ := doc["delivery_address_id"].(string)
		custName := "Customer"
		custAddr := ""
		custLat := 0.0
		custLng := 0.0
		if addrID != "" {
			if addr, aErr := w.awService.GetAddress(addrID); aErr == nil && addr != nil {
				custAddr, _ = addr["full_address"].(string)
				custLat, _ = addr["latitude"].(float64)
				custLng, _ = addr["longitude"].(float64)
			}
		}
		// Try to get customer name from user doc
		if customerID != "" {
			if user, uErr := w.awService.GetUser(customerID); uErr == nil && user != nil {
				if n, _ := user["name"].(string); n != "" {
					custName = n
				}
			}
		}

		// 6. Calculate distances and estimated earning
		pickupDistKm := w.geoService.Distance(restLat, restLng, restLat, restLng) // rider → restaurant (approx 0 for now)
		deliveryDistKm := 0.0
		if custLat != 0 && custLng != 0 {
			deliveryDistKm = w.geoService.Distance(restLat, restLng, custLat, custLng)
		}
		totalDistKm := pickupDistKm + deliveryDistKm

		// Estimate earning: delivery_fee from the order or calculate base
		deliveryFee := getFloatField(doc, "delivery_fee")
		tip := getFloatField(doc, "tip")
		estimatedEarning := deliveryFee + tip
		if estimatedEarning == 0 {
			// Fallback: base ₹30 + ₹10/km
			estimatedEarning = 30 + math.Round(totalDistKm*10)
		}

		riderID := riderIDs[0]
		expiresAt := time.Now().UTC().Add(30 * time.Second).Format(time.RFC3339)
		orderNumber, _ := doc["order_number"].(string)

		// 7. Create delivery request document in Appwrite
		reqData := map[string]interface{}{
			"order_id":   orderID,
			"rider_id":   riderID,
			"status":     "pending",
			"created_at": time.Now().UTC().Format(time.RFC3339),
		}
		_, err = w.awService.CreateDeliveryRequest("", reqData)
		if err != nil {
			log.Printf("[worker] DeliveryMatcher: failed creating delivery request for order %s: %v", orderID, err)
			_ = w.redisClient.Del(ctx, pendingKey)
			continue
		}

		// Update Redis lock with rider ID for reference
		_ = w.redisClient.Set(ctx, pendingKey, riderID, 60*time.Second)

		log.Printf("[worker] DeliveryMatcher: assigned rider %s to order %s", riderID, orderID)

		// 8. Build enriched order map for Flutter DeliveryRequest.fromMap()
		orderItems, _ := doc["items"].([]interface{})
		enrichedOrder := map[string]interface{}{
			"$id":                   orderID,
			"order_number":          orderNumber,
			"customer_id":           customerID,
			"restaurant_id":         restaurantID,
			"restaurant_name":       restName,
			"delivery_address_id":   addrID,
			"delivery_address":      custAddr,
			"delivery_latitude":     custLat,
			"delivery_longitude":    custLng,
			"restaurant_latitude":   restLat,
			"restaurant_longitude":  restLng,
			"items":                 orderItems,
			"item_total":            getFloatField(doc, "item_total"),
			"delivery_fee":          deliveryFee,
			"platform_fee":          getFloatField(doc, "platform_fee"),
			"gst":                   getFloatField(doc, "gst"),
			"discount":              getFloatField(doc, "discount"),
			"tip":                   tip,
			"grand_total":           getFloatField(doc, "grand_total"),
			"payment_method":        doc["payment_method"],
			"payment_status":        doc["payment_status"],
			"status":                "ready",
			"special_instructions":  doc["special_instructions"],
			"placed_at":             doc["placed_at"],
		}

		// 9. Send enriched WS payload matching DeliveryRequest.fromMap() schema
		w.broadcaster.BroadcastDeliveryRequestFull(riderID, map[string]interface{}{
			"$id":                  fmt.Sprintf("req_%s_%s", orderID, riderID),
			"order":               enrichedOrder,
			"restaurant_name":     restName,
			"restaurant_cuisine":  restCuisine,
			"restaurant_address":  restAddr,
			"restaurant_latitude": restLat,
			"restaurant_longitude": restLng,
			"customer_name":       custName,
			"customer_address":    custAddr,
			"customer_latitude":   custLat,
			"customer_longitude":  custLng,
			"pickup_distance_km":  math.Round(pickupDistKm*10) / 10,
			"delivery_distance_km": math.Round(deliveryDistKm*10) / 10,
			"distance_km":         math.Round(totalDistKm*10) / 10,
			"estimated_earning":   estimatedEarning,
			"special_instructions": doc["special_instructions"],
			"expires_at":          expiresAt,
		})

		// 10. Notify customer that a rider is being assigned
		if w.broadcaster != nil && customerID != "" {
			w.broadcaster.BroadcastOrderUpdate(customerID, orderID, "rider_assigned", "A delivery partner is on the way")
		}
	}
}

// getFloatField safely extracts a float64 from a map
func getFloatField(m map[string]interface{}, key string) float64 {
	switch v := m[key].(type) {
	case float64:
		return v
	case float32:
		return float64(v)
	case int:
		return float64(v)
	case int64:
		return float64(v)
	default:
		return 0
	}
}

// findNearbyRiders queries Redis geo set for online riders within radiusKm
func (w *DeliveryMatcher) findNearbyRiders(ctx context.Context, lat, lng, radiusKm float64) ([]string, error) {
	ids, err := w.redisClient.GeoSearch(ctx, "rider_locations", &redis.GeoSearchQuery{
		Longitude:  lng,
		Latitude:   lat,
		Radius:     radiusKm,
		RadiusUnit: "km",
		Sort:       "ASC",
		Count:      5,
	})
	if err != nil {
		return nil, err
	}
	return ids, nil
}
