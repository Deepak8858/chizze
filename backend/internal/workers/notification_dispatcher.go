package workers

import (
	"context"
	"encoding/json"
	"log"
	"time"

	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/internal/websocket"
	redispkg "github.com/chizze/backend/pkg/redis"
)

// NotificationDispatcher processes queued notifications from Redis and sends them
// via WebSocket and push notifications. This decouples notification generation
// from delivery, ensuring handlers don't block on notification sending.
type NotificationDispatcher struct {
	awService   *services.AppwriteService
	hub         *websocket.Hub
	redisClient *redispkg.Client
	interval    time.Duration
}

func NewNotificationDispatcher(
	awService *services.AppwriteService,
	hub *websocket.Hub,
	redisClient *redispkg.Client,
	interval time.Duration,
) *NotificationDispatcher {
	return &NotificationDispatcher{
		awService:   awService,
		hub:         hub,
		redisClient: redisClient,
		interval:    interval,
	}
}

func (w *NotificationDispatcher) Start(ctx context.Context) {
	log.Println("[worker] NotificationDispatcher started (interval: " + w.interval.String() + ")")

	for {
		select {
		case <-ctx.Done():
			log.Println("[worker] NotificationDispatcher stopped")
			return
		default:
			w.processQueue(ctx)
		}
	}
}

// NotificationPayload is the structure of a queued notification
type NotificationPayload struct {
	UserID string `json:"user_id"`
	Title  string `json:"title"`
	Body   string `json:"body"`
	Type   string `json:"type"`
	Data   map[string]interface{} `json:"data,omitempty"`
}

const notificationQueueKey = "notification_queue"

// QueueNotification adds a notification to the Redis queue for async processing.
// This is the public API that handlers should call instead of sending directly.
func QueueNotification(ctx context.Context, redisClient *redispkg.Client, notif NotificationPayload) error {
	data, err := json.Marshal(notif)
	if err != nil {
		return err
	}
	_, lpushErr := redisClient.LPush(ctx, notificationQueueKey, data)
	return lpushErr
}

func (w *NotificationDispatcher) processQueue(ctx context.Context) {
	// Block-pop from Redis queue with 5s timeout (avoids busy loop)
	result, err := w.redisClient.BRPop(ctx, 5*time.Second, notificationQueueKey)
	if err != nil {
		// Timeout or context cancelled — just return
		return
	}
	if len(result) < 2 {
		return
	}

	var notif NotificationPayload
	if err := json.Unmarshal([]byte(result[1]), &notif); err != nil {
		log.Printf("[worker] NotificationDispatcher: invalid payload: %v", err)
		return
	}

	// 1. Store notification in Appwrite
	notifData := map[string]interface{}{
		"user_id":    notif.UserID,
		"title":      notif.Title,
		"body":       notif.Body,
		"type":       notif.Type,
		"is_read":    false,
		"created_at": time.Now().UTC().Format(time.RFC3339),
	}
	if notif.Data != nil {
		dataJSON, _ := json.Marshal(notif.Data)
		notifData["data"] = string(dataJSON)
	}

	_, err = w.awService.CreateNotification("", notifData)
	if err != nil {
		log.Printf("[worker] NotificationDispatcher: failed storing notification for %s: %v", notif.UserID, err)
		// Don't return — still try to send real-time
	}

	// 2. Send via WebSocket
	evt, _ := json.Marshal(map[string]interface{}{
		"type": "notification",
		"payload": map[string]interface{}{
			"title": notif.Title,
			"body":  notif.Body,
			"type":  notif.Type,
			"data":  notif.Data,
		},
		"timestamp": time.Now().UTC().Format(time.RFC3339),
	})
	w.hub.SendToUser(notif.UserID, evt)

	// 3. TODO: Send FCM push notification via Firebase Admin SDK
	// This would be implemented when Firebase is configured
	// firebase.SendPush(notif.UserID, notif.Title, notif.Body)

	log.Printf("[worker] NotificationDispatcher: delivered to %s — %s", notif.UserID, notif.Title)
}
