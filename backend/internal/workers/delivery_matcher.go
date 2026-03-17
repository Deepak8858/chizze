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
			w.Process(ctx)
		}
	}
}

// Process runs the matching logic. Exported so it can be called on-demand
// (e.g. immediately when an order status changes to "ready").
func (w *DeliveryMatcher) Process(ctx context.Context) {
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

		// 2. Check Redis lock to prevent re-matching an already-pending order.
		// Keep a finite TTL as a safety net; accept/reject paths clear it immediately.
		pendingKey := "pending_delivery:" + orderID
		acquired, lockErr := w.redisClient.SetNX(ctx, pendingKey, "1", 2*time.Minute)
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
		restPhone, _ := restaurant["phone"].(string)
		// Fall back to the restaurant owner's phone if restaurant has no direct phone
		if restPhone == "" {
			if ownerID, _ := restaurant["owner_id"].(string); ownerID != "" {
				if owner, oErr := w.awService.GetUser(ownerID); oErr == nil && owner != nil {
					restPhone, _ = owner["phone"].(string)
				}
			}
		}

		// 4. Find online riders within 15 km via Redis geo index
		riderIDs, err := w.findNearbyRiders(ctx, restLat, restLng, 15.0)
		if err != nil || len(riderIDs) == 0 {
			log.Printf("[worker] DeliveryMatcher: no riders near restaurant %s for order %s", restaurantID, orderID)
			_ = w.redisClient.Del(ctx, pendingKey)
			continue
		}

		// 4b. Filter out riders who already rejected this order
		rejectedKey := "rejected_riders:" + orderID
		rejectedSet, _ := w.redisClient.SMembers(ctx, rejectedKey)
		if len(rejectedSet) > 0 {
			rejectedMap := make(map[string]bool, len(rejectedSet))
			for _, rid := range rejectedSet {
				rejectedMap[rid] = true
			}
			var filtered []string
			for _, rid := range riderIDs {
				if !rejectedMap[rid] {
					filtered = append(filtered, rid)
				}
			}
			riderIDs = filtered
		}
		if len(riderIDs) == 0 {
			log.Printf("[worker] DeliveryMatcher: all nearby riders rejected order %s — clearing lock for retry", orderID)
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
		// Try to get customer name and phone from user doc
		custPhone := ""
		if customerID != "" {
			if user, uErr := w.awService.GetUser(customerID); uErr == nil && user != nil {
				if n, _ := user["name"].(string); n != "" {
					custName = n
				}
				if p, _ := user["phone"].(string); p != "" {
					custPhone = p
				}
			}
		}

		// 6. Calculate distances and estimated earning
		// Look up rider's current position from Redis geo set
		pickupDistKm := 0.0
		if positions, gErr := w.redisClient.GeoPos(ctx, "rider_locations", riderIDs[0]); gErr == nil && len(positions) > 0 && positions[0] != nil {
			riderLat := positions[0].Latitude
			riderLng := positions[0].Longitude
			pickupDistKm = w.geoService.Distance(riderLat, riderLng, restLat, restLng)
		}
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
			"order_id":             orderID,
			"rider_id":            riderID,
			"status":              "pending",
			"restaurant_name":     restName,
			"restaurant_address":  restAddr,
			"restaurant_latitude": restLat,
			"restaurant_longitude": restLng,
			"customer_address":    custAddr,
			"customer_latitude":   custLat,
			"customer_longitude":  custLng,
			"distance_km":         math.Round(totalDistKm*10) / 10,
			"estimated_earning":   estimatedEarning,
			"expires_at":          expiresAt,
		}
		_, err = w.awService.CreateDeliveryRequest("unique()", reqData)
		if err != nil {
			log.Printf("[worker] DeliveryMatcher: failed creating delivery request for order %s: %v", orderID, err)
			_ = w.redisClient.Del(ctx, pendingKey)
			continue
		}

		// Keep TTL consistent with SetNX while accept/reject remains the fast clear path.
		_ = w.redisClient.Set(ctx, pendingKey, riderID, 2*time.Minute)

		log.Printf("[worker] DeliveryMatcher: assigned rider %s to order %s", riderID, orderID)

		// 8. Build enriched order map for Flutter DeliveryRequest.fromMap()
		// items is stored as a JSON string in Appwrite — pass it through as-is
		// so the Flutter _parseItems() can decode it.
		orderItems := doc["items"]
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
			"customer_name":         custName,
		}

		// 9. Send enriched WS payload matching DeliveryRequest.fromMap() schema
		w.broadcaster.BroadcastDeliveryRequestFull(riderID, map[string]interface{}{
			"$id":                  fmt.Sprintf("req_%s_%s", orderID, riderID),
			"order":               enrichedOrder,
			"restaurant_name":     restName,
			"restaurant_cuisine":  restCuisine,
			"restaurant_address":  restAddr,
			"restaurant_phone":    restPhone,
			"restaurant_latitude": restLat,
			"restaurant_longitude": restLng,
			"customer_name":       custName,
			"customer_phone":      custPhone,
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

		// Note: do NOT notify customer here — the rider has not accepted yet.
		// Customer will be notified when the rider actually accepts (in AcceptOrder handler).
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
