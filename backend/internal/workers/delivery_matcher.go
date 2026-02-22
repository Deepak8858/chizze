package workers

import (
	"context"
	"encoding/json"
	"log"
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
	// 1. Find orders with status "ready" and no delivery_partner_id
	queries := []string{
		appwrite.QueryEqual("status", "ready"),
		appwrite.QueryIsNull("delivery_partner_id"),
	}

	result, err := w.awService.ListOrders(queries)
	if err != nil {
		log.Printf("[worker] DeliveryMatcher error listing orders: %v", err)
		return
	}
	if result == nil || len(result.Documents) == 0 {
		return
	}

	for _, doc := range result.Documents {
		orderID, _ := doc["$id"].(string)
		restaurantID, _ := doc["restaurant_id"].(string)
		customerID, _ := doc["customer_id"].(string)

		// 2. Get restaurant location
		restaurant, err := w.awService.GetRestaurant(restaurantID)
		if err != nil {
			log.Printf("[worker] DeliveryMatcher: can't get restaurant %s: %v", restaurantID, err)
			continue
		}

		restLng, _ := restaurant["longitude"].(float64)
		restLat, _ := restaurant["latitude"].(float64)

		// 3. Find online riders within 5 km via Redis geo index
		riderIDs, err := w.findNearbyRiders(ctx, restLat, restLng, 5.0)
		if err != nil || len(riderIDs) == 0 {
			log.Printf("[worker] DeliveryMatcher: no riders near restaurant %s for order %s", restaurantID, orderID)
			continue
		}

		// 4. Create delivery request for the nearest rider
		riderID := riderIDs[0]
		reqData := map[string]interface{}{
			"order_id":   orderID,
			"rider_id":   riderID,
			"status":     "pending",
			"created_at": time.Now().UTC().Format(time.RFC3339),
		}
		_, err = w.awService.CreateDeliveryRequest("", reqData)
		if err != nil {
			log.Printf("[worker] DeliveryMatcher: failed creating delivery request for order %s: %v", orderID, err)
			continue
		}

		log.Printf("[worker] DeliveryMatcher: assigned rider %s to order %s", riderID, orderID)

		// 5. Notify rider via WebSocket
		evt, _ := json.Marshal(map[string]interface{}{
			"type":    "delivery_request",
			"payload": map[string]interface{}{"order_id": orderID, "restaurant_id": restaurantID},
		})
		w.hub.SendToUser(riderID, evt)

		// 6. Notify customer that a rider is being assigned
		custEvt, _ := json.Marshal(map[string]interface{}{
			"type":    "order_update",
			"payload": map[string]interface{}{"order_id": orderID, "status": "rider_assigned"},
		})
		w.hub.SendToUser(customerID, custEvt)
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
