package workers

import (
	"context"
	"encoding/json"
	"log"
	"time"

	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/internal/websocket"
	"github.com/chizze/backend/pkg/appwrite"
)

// ScheduledOrderProcessor checks for scheduled orders whose time has arrived
// and converts them into real orders.
type ScheduledOrderProcessor struct {
	awService *services.AppwriteService
	hub       *websocket.Hub
	interval  time.Duration
}

func NewScheduledOrderProcessor(
	awService *services.AppwriteService,
	hub *websocket.Hub,
	interval time.Duration,
) *ScheduledOrderProcessor {
	return &ScheduledOrderProcessor{
		awService: awService,
		hub:       hub,
		interval:  interval,
	}
}

func (w *ScheduledOrderProcessor) Start(ctx context.Context) {
	ticker := time.NewTicker(w.interval)
	defer ticker.Stop()

	log.Println("[worker] ScheduledOrderProcessor started (interval: " + w.interval.String() + ")")

	for {
		select {
		case <-ctx.Done():
			log.Println("[worker] ScheduledOrderProcessor stopped")
			return
		case <-ticker.C:
			w.process()
		}
	}
}

func (w *ScheduledOrderProcessor) process() {
	// Find pending scheduled orders
	queries := []string{
		appwrite.QueryEqual("status", "scheduled"),
	}

	result, err := w.awService.ListScheduledOrders("")
	if err != nil {
		log.Printf("[worker] ScheduledOrderProcessor error: %v", err)
		return
	}
	_ = queries // queries would be used with a proper list method

	if result == nil || len(result.Documents) == 0 {
		return
	}

	now := time.Now()
	processedCount := 0

	for _, doc := range result.Documents {
		scheduledFor, _ := doc["scheduled_for"].(string)
		scheduledTime, err := time.Parse(time.RFC3339, scheduledFor)
		if err != nil {
			continue
		}

		// Process if scheduled time is within the next 2 minutes (to allow prep time)
		if now.After(scheduledTime.Add(-2 * time.Minute)) {
			orderID, _ := doc["$id"].(string)
			userID, _ := doc["user_id"].(string)

			// Update scheduled order status to "placed"
			updates := map[string]interface{}{
				"status": "placed",
			}
			_, err := w.awService.UpdateScheduledOrder(orderID, updates)
			if err != nil {
				log.Printf("[worker] ScheduledOrderProcessor: failed updating %s: %v", orderID, err)
				continue
			}

			processedCount++

			// Notify user that their scheduled order is being placed
			evt, _ := json.Marshal(map[string]interface{}{
				"type": "order_update",
				"payload": map[string]interface{}{
					"order_id": orderID,
					"status":   "placed",
					"message":  "Your scheduled order is being prepared!",
				},
				"timestamp": now.UTC().Format(time.RFC3339),
			})
			w.hub.SendToUser(userID, evt)

			log.Printf("[worker] ScheduledOrderProcessor: placed scheduled order %s for user %s", orderID, userID)
		}
	}

	if processedCount > 0 {
		log.Printf("[worker] ScheduledOrderProcessor: processed %d scheduled orders", processedCount)
	}
}
