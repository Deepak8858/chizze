package handlers

import (
	"encoding/json"
	"log"
	"strings"

	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/internal/websocket"
)

// chatPayload is the shape Flutter sends over the WebSocket for chat messages.
// The outer envelope is { type: "chat_message", payload: {...} }.
type chatPayload struct {
	Type    string `json:"type"`
	Payload struct {
		OrderID string `json:"order_id"`
		Message string `json:"message"`
	} `json:"payload"`
}

// Max chat message length — long enough for a paragraph, short enough to stop
// abuse. Longer messages are truncated rather than rejected so the UI doesn't
// silently drop them.
const maxChatMessageLen = 1000

// NewChatRouter returns a websocket.IncomingHandler that routes chat messages
// between the customer, delivery partner, and restaurant owner of an active
// order. The sender is authenticated via the WS Client's UserID/Role — the
// WS middleware already verified the JWT before upgrading.
//
// Authorization rules:
//   - Sender must be one of: customer_id, delivery_partner_id, or restaurant owner
//   - Order must exist and not be delivered/cancelled
//   - Each message is forwarded to the OTHER two participants (when resolvable)
//
// Invalid / unauthorized messages are logged and dropped — the sender gets no
// error event to avoid leaking "does this order exist" information.
func NewChatRouter(aw *services.AppwriteService, broadcaster *websocket.EventBroadcaster) websocket.IncomingHandler {
	return func(client *websocket.Client, raw []byte) {
		var env chatPayload
		if err := json.Unmarshal(raw, &env); err != nil {
			// Not JSON or malformed — silently drop (could be ping/keepalive).
			return
		}
		if env.Type != "chat_message" {
			return
		}
		orderID := strings.TrimSpace(env.Payload.OrderID)
		message := strings.TrimSpace(env.Payload.Message)
		if orderID == "" || message == "" {
			return
		}
		if len(message) > maxChatMessageLen {
			message = message[:maxChatMessageLen]
		}

		order, err := aw.GetOrder(orderID)
		if err != nil || order == nil {
			log.Printf("[chat] order %s not found for sender %s", orderID, client.UserID)
			return
		}

		// Reject chat on terminal orders so customers can't be spammed after delivery.
		status, _ := order["status"].(string)
		if status == "delivered" || status == "cancelled" {
			return
		}

		customerID, _ := order["customer_id"].(string)
		riderID, _ := order["delivery_partner_id"].(string)
		restaurantID, _ := order["restaurant_id"].(string)

		// Resolve restaurant owner for authorization + fan-out.
		var ownerID string
		if restaurantID != "" {
			if rest, rErr := aw.GetRestaurant(restaurantID); rErr == nil && rest != nil {
				ownerID, _ = rest["owner_id"].(string)
			}
		}

		// Verify sender is a participant of this order. Admins are also allowed
		// so support staff can intervene.
		sender := client.UserID
		senderRole := client.Role
		isParticipant := sender == customerID || sender == riderID || sender == ownerID ||
			senderRole == "admin" || senderRole == "super_admin"
		if !isParticipant {
			log.Printf("[chat] sender %s (role=%s) is not a participant of order %s — dropped", sender, senderRole, orderID)
			return
		}

		// Fan out to everyone EXCEPT the sender. Recipients with no active WS
		// connection just won't receive it — the client falls back to polling
		// the persisted notification (chat messages are ephemeral here and
		// intentionally not persisted, per flow.md §2.2.7).
		recipients := make([]string, 0, 3)
		for _, rid := range []string{customerID, riderID, ownerID} {
			if rid == "" || rid == sender {
				continue
			}
			recipients = append(recipients, rid)
		}

		for _, rid := range recipients {
			broadcaster.BroadcastChatMessage(rid, orderID, sender, senderRole, message)
		}
	}
}
