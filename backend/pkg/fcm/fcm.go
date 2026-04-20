package fcm

import (
	"context"
	"errors"
	"fmt"
	"log"
	"time"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"google.golang.org/api/option"
)

// Client sends Firebase Cloud Messaging push notifications using the
// HTTP v1 API via the Firebase Admin SDK. The legacy FCM HTTP API
// (https://fcm.googleapis.com/fcm/send) that this client previously used
// was decommissioned by Google on June 20, 2024 — hence the migration.
//
// Configure via:
//   - FIREBASE_CREDENTIALS_JSON = absolute path to a service account JSON
//     (Firebase Console → Project Settings → Service Accounts → Generate
//     new private key)
//   - FIREBASE_PROJECT_ID       = the Firebase project ID (e.g. chizze-app)
type Client struct {
	messaging *messaging.Client
}

// NewClient creates an FCM client backed by the Firebase Admin SDK.
// credentialsPath is the path to a service account JSON; projectID is
// the Firebase project ID. Returns nil (FCM disabled) when either is
// empty or when Firebase initialisation fails — callers must treat a
// nil client as a soft no-op.
func NewClient(credentialsPath, projectID string) *Client {
	if credentialsPath == "" || projectID == "" {
		return nil
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	app, err := firebase.NewApp(ctx,
		&firebase.Config{ProjectID: projectID},
		option.WithCredentialsFile(credentialsPath),
	)
	if err != nil {
		log.Printf("[fcm] Firebase app init failed (push disabled): %v", err)
		return nil
	}

	msgClient, err := app.Messaging(ctx)
	if err != nil {
		log.Printf("[fcm] Messaging client init failed (push disabled): %v", err)
		return nil
	}

	log.Printf("[fcm] Firebase Admin SDK initialised (project=%s)", projectID)
	return &Client{messaging: msgClient}
}

// DeliveryRequestPayload is the data sent to a rider for a new delivery request.
type DeliveryRequestPayload struct {
	OrderID          string
	RestaurantName   string
	EstimatedEarning float64
}

// SendDeliveryRequest sends a high-priority FCM push to a single device
// token. Wakes the rider's app from background/killed state and triggers
// the delivery flow. Honoured channel: `delivery_requests` on Android.
func (c *Client) SendDeliveryRequest(ctx context.Context, fcmToken string, p DeliveryRequestPayload) error {
	if c == nil || fcmToken == "" {
		return nil
	}
	if len(fcmToken) < 20 {
		return nil
	}

	body := fmt.Sprintf("From %s • ₹%.0f earning", p.RestaurantName, p.EstimatedEarning)

	message := &messaging.Message{
		Token: fcmToken,
		Notification: &messaging.Notification{
			Title: "🛵 New Delivery Request",
			Body:  body,
		},
		Data: map[string]string{
			"type":              "delivery_request",
			"order_id":          p.OrderID,
			"restaurant_name":   p.RestaurantName,
			"estimated_earning": fmt.Sprintf("%.0f", p.EstimatedEarning),
			"click_action":      "FLUTTER_NOTIFICATION_CLICK",
		},
		Android: &messaging.AndroidConfig{
			Priority: "high",
			TTL:      durationPtr(30 * time.Second),
			Notification: &messaging.AndroidNotification{
				ChannelID: "delivery_requests",
				Sound:     "mkb",
			},
		},
		APNS: &messaging.APNSConfig{
			Headers: map[string]string{"apns-priority": "10"},
			Payload: &messaging.APNSPayload{
				Aps: &messaging.Aps{
					ContentAvailable: true,
					Sound:            "mkb.mp3",
				},
			},
		},
	}

	return c.send(ctx, message, fcmToken)
}

// SendPush sends a general push notification to a device token.
// `data` populates the FCM data payload (used for deep-link routing).
// When data contains `android_channel_id`, it is also set on the
// Android notification so the device routes it to the right tray
// channel (e.g. `new_orders`, `chizze_main`).
func (c *Client) SendPush(ctx context.Context, fcmToken, title, body string, data map[string]string) error {
	if c == nil || fcmToken == "" {
		return nil
	}
	if len(fcmToken) < 20 {
		return nil
	}

	channelID := "chizze_main"
	if ch, ok := data["android_channel_id"]; ok && ch != "" {
		channelID = ch
	}

	message := &messaging.Message{
		Token: fcmToken,
		Notification: &messaging.Notification{
			Title: title,
			Body:  body,
		},
		Data: data,
		Android: &messaging.AndroidConfig{
			Priority: "high",
			Notification: &messaging.AndroidNotification{
				ChannelID: channelID,
				Sound:     "default",
			},
		},
		APNS: &messaging.APNSConfig{
			Headers: map[string]string{"apns-priority": "10"},
			Payload: &messaging.APNSPayload{
				Aps: &messaging.Aps{Sound: "default"},
			},
		},
	}

	return c.send(ctx, message, fcmToken)
}

// send dispatches a message and logs any failure. Returns the Firebase
// error so callers can log at their own site too (double-logging is
// intentional — FCM failures are easy to miss in production).
func (c *Client) send(ctx context.Context, m *messaging.Message, token string) error {
	if ctx == nil {
		ctx = context.Background()
	}
	// Guard against callers passing the server's request context (which
	// cancels on client disconnect) — FCM push is fire-and-forget.
	sendCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	resp, err := c.messaging.Send(sendCtx, m)
	if err != nil {
		isUnregistered := messaging.IsUnregistered(err) || messaging.IsRegistrationTokenNotRegistered(err)
		if isUnregistered {
			log.Printf("[fcm] token unregistered (device uninstalled?) token=%s…", truncateToken(token))
			return errUnregisteredToken
		}
		log.Printf("[fcm] Send failed token=%s… err=%v", truncateToken(token), err)
		return err
	}
	log.Printf("[fcm] Sent id=%s token=%s…", resp, truncateToken(token))
	return nil
}

// ErrUnregisteredToken is returned when FCM reports a token is no longer
// valid (app uninstalled, token rotated, etc.). Callers may want to
// clear the stored fcm_token on the user doc to stop retrying.
var errUnregisteredToken = errors.New("fcm: token unregistered")

// IsUnregisteredToken reports whether err indicates the device token is
// no longer valid. Thin wrapper so callers don't import this package's
// internal sentinel.
func IsUnregisteredToken(err error) bool {
	return errors.Is(err, errUnregisteredToken)
}

func truncateToken(t string) string {
	if len(t) <= 12 {
		return t
	}
	return t[:12]
}

func durationPtr(d time.Duration) *time.Duration {
	return &d
}
