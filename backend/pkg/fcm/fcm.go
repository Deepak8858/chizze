package fcm

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"time"
)

// Client sends Firebase Cloud Messaging push notifications using
// the FCM Legacy HTTP API (v1 compatible endpoint).
// Configure via FCM_SERVER_KEY environment variable.
type Client struct {
	serverKey  string
	httpClient *http.Client
}

// NewClient creates an FCM client. serverKey is the FCM Server Key
// from Firebase Console → Project Settings → Cloud Messaging.
// Returns nil if serverKey is empty (FCM disabled).
func NewClient(serverKey string) *Client {
	if serverKey == "" {
		return nil
	}
	return &Client{
		serverKey: serverKey,
		httpClient: &http.Client{
			Timeout: 5 * time.Second,
		},
	}
}

// DeliveryRequestPayload is the data sent to a rider for a new delivery request.
type DeliveryRequestPayload struct {
	OrderID          string
	RestaurantName   string
	EstimatedEarning float64
}

// SendDeliveryRequest sends an FCM data+notification push to a single device token.
// This wakes the app from background/killed state and triggers the delivery flow.
func (c *Client) SendDeliveryRequest(ctx context.Context, fcmToken string, p DeliveryRequestPayload) error {
	if c == nil || fcmToken == "" {
		return nil
	}
	// Ignore dev/test tokens
	if len(fcmToken) < 20 {
		return nil
	}

	body := map[string]interface{}{
		"to":                fcmToken,
		"priority":          "high",
		"content_available": true, // wake iOS
		// Data-only message so the Flutter background handler can process it
		// without showing a system notification (the app handles the UI itself)
		"data": map[string]string{
			"type":              "delivery_request",
			"order_id":          p.OrderID,
			"restaurant_name":   p.RestaurantName,
			"estimated_earning": fmt.Sprintf("%.0f", p.EstimatedEarning),
			"click_action":      "FLUTTER_NOTIFICATION_CLICK",
		},
		// Notification block so device shows heads-up even if app is killed
		"notification": map[string]interface{}{
			"title":              "🛵 New Delivery Request",
			"body":               fmt.Sprintf("From %s • ₹%.0f earning", p.RestaurantName, p.EstimatedEarning),
			"sound":              "mkb", // custom sound (must be bundled in iOS app)
			"android_channel_id": "delivery_requests",
		},
		"android": map[string]interface{}{
			"priority": "high",
			"ttl":      "30s", // matches the 30s rider countdown
		},
		"apns": map[string]interface{}{
			"headers": map[string]string{
				"apns-priority": "10",
			},
			"payload": map[string]interface{}{
				"aps": map[string]interface{}{
					"content-available": 1,
					"sound":             "mkb.mp3",
				},
			},
		},
	}

	return c.send(ctx, body)
}

// SendPush sends a general push notification to a device token.
func (c *Client) SendPush(ctx context.Context, fcmToken, title, body string, data map[string]string) error {
	if c == nil || fcmToken == "" {
		return nil
	}
	if len(fcmToken) < 20 {
		return nil
	}

	payload := map[string]interface{}{
		"to":       fcmToken,
		"priority": "high",
		"data":     data,
		"notification": map[string]string{
			"title": title,
			"body":  body,
		},
	}
	return c.send(ctx, payload)
}

func (c *Client) send(ctx context.Context, payload interface{}) error {
	data, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("fcm: marshal error: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		"https://fcm.googleapis.com/fcm/send", bytes.NewReader(data))
	if err != nil {
		return fmt.Errorf("fcm: request build error: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "key="+c.serverKey)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("fcm: HTTP error: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("fcm: server returned %d: %s", resp.StatusCode, string(body))
	}

	// Parse response to check for per-token failures
	var result struct {
		Success int `json:"success"`
		Failure int `json:"failure"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err == nil {
		if result.Failure > 0 {
			log.Printf("[fcm] Send had %d failures (success: %d)", result.Failure, result.Success)
		}
	}

	return nil
}
