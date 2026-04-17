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
)

// OrderTimeout periodically checks for orders that have been in "placed" status for too long
// and auto-cancels them if the restaurant hasn't confirmed within the timeout period.
//
// Behaviour: an order is eligible for auto-cancel only if the owner was actually
// reachable when the order was placed (i.e. we saw WS active OR FCM was sent).
// If neither delivery channel worked, PlaceOrder would have recorded no flag in
// Redis — those orders are logged as STUCK_ORDER instead of cancelled, because
// auto-cancelling an order the restaurant never even saw is worse UX than
// letting a human resolve it via admin.
type OrderTimeout struct {
	awService *services.AppwriteService
	hub       *websocket.Hub
	redis     *redispkg.Client
	interval  time.Duration
	timeout   time.Duration
}

func NewOrderTimeout(
	awService *services.AppwriteService,
	hub *websocket.Hub,
	redis *redispkg.Client,
	interval time.Duration,
	timeout time.Duration,
) *OrderTimeout {
	return &OrderTimeout{
		awService: awService,
		hub:       hub,
		redis:     redis,
		interval:  interval,
		timeout:   timeout,
	}
}

func (w *OrderTimeout) Start(ctx context.Context) {
	ticker := time.NewTicker(w.interval)
	defer ticker.Stop()

	log.Println("[worker] OrderTimeout started (interval: " + w.interval.String() + ", timeout: " + w.timeout.String() + ")")

	for {
		select {
		case <-ctx.Done():
			log.Println("[worker] OrderTimeout stopped")
			return
		case <-ticker.C:
			w.process()
		}
	}
}

func (w *OrderTimeout) process() {
	// Find orders with status "placed"
	queries := []string{
		appwrite.QueryEqual("status", "placed"),
	}

	result, err := w.awService.ListOrders(queries)
	if err != nil {
		log.Printf("[worker] OrderTimeout error listing orders: %v", err)
		return
	}
	if result == nil || len(result.Documents) == 0 {
		return
	}

	now := time.Now()
	cancelledCount := 0

	for _, doc := range result.Documents {
		orderID, _ := doc["$id"].(string)
		customerID, _ := doc["customer_id"].(string)
		restaurantID, _ := doc["restaurant_id"].(string)
		createdAtStr, _ := doc["$createdAt"].(string)

		// Parse order creation time
		createdAt, err := time.Parse(time.RFC3339, createdAtStr)
		if err != nil {
			continue
		}

		// If order is older than timeout, cancel it
		if now.Sub(createdAt) > w.timeout {
			// Skip auto-cancel if the restaurant owner was never reachable.
			// PlaceOrder writes order_notif:<id>:ws or :fcm when a notification
			// actually went out. Missing both means the order is stuck and
			// needs human intervention (admin dashboard) rather than silent
			// cancel — silent cancel hides the bug from ops visibility.
			if w.redis != nil {
				ctx := context.Background()
				wsFlag, _ := w.redis.Get(ctx, "order_notif:"+orderID+":ws")
				fcmFlag, _ := w.redis.Get(ctx, "order_notif:"+orderID+":fcm")
				if wsFlag == "" && fcmFlag == "" {
					log.Printf("[worker] OrderTimeout: STUCK_ORDER %s — restaurant owner was unreachable when placed (no WS, no FCM). Leaving for admin review.", orderID)
					continue
				}
			}
			log.Printf("[worker] OrderTimeout: auto-canceling order %s (placed %v ago, limit %v)", orderID, now.Sub(createdAt).Round(time.Second), w.timeout)

			updates := map[string]interface{}{
				"status":              "cancelled",
				"cancellation_reason": "auto_timeout",
				"cancelled_by":        "system",
				"cancelled_at":        now.Format(time.RFC3339),
			}

			_, err := w.awService.UpdateOrder(orderID, updates)
			if err != nil {
				log.Printf("[worker] OrderTimeout error canceling order %s: %v", orderID, err)
				continue
			}
			cancelledCount++

			// Notify customer via WebSocket
			evt, _ := json.Marshal(map[string]interface{}{
				"type": "order_update",
				"payload": map[string]interface{}{
					"order_id": orderID,
					"status":   "cancelled",
					"reason":   "Restaurant did not confirm your order in time. You will be refunded.",
				},
			})
			w.hub.SendToUser(customerID, evt)

			// Notify restaurant partner via WebSocket
			partnerEvt, _ := json.Marshal(map[string]interface{}{
				"type": "order_update",
				"payload": map[string]interface{}{
					"order_id": orderID,
					"status":   "cancelled",
					"reason":   "Order auto-cancelled due to confirmation timeout.",
				},
			})
			w.hub.SendToUser(restaurantID, partnerEvt)
		}
	}

	if cancelledCount > 0 {
		log.Printf("[worker] OrderTimeout: cancelled %d timed-out orders", cancelledCount)
	}
}
