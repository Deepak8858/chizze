package websocket

import (
	"encoding/json"
	"log"
	"time"
)

// EventType defines the types of real-time events
type EventType string

const (
	EventOrderUpdate       EventType = "order_update"
	EventDeliveryRequest   EventType = "delivery_request"
	EventDeliveryLocation  EventType = "delivery_location"
	EventNewOrder          EventType = "new_order"
	EventNotification      EventType = "notification"
	EventRiderStatusChange EventType = "rider_status_change"
	EventRestaurantUpdate  EventType = "restaurant_update"
)

// Event represents a real-time event to be sent via WebSocket
type Event struct {
	Type      EventType   `json:"type"`
	Payload   interface{} `json:"payload"`
	Timestamp string      `json:"timestamp"`
}

// EventBroadcaster provides methods for broadcasting typed events to users via the Hub
type EventBroadcaster struct {
	hub *Hub
}

// NewEventBroadcaster creates a new event broadcaster
func NewEventBroadcaster(hub *Hub) *EventBroadcaster {
	return &EventBroadcaster{hub: hub}
}

// BroadcastOrderUpdate sends an order status update to the customer
func (b *EventBroadcaster) BroadcastOrderUpdate(customerID, orderID, status, message string) {
	b.sendToUser(customerID, EventOrderUpdate, map[string]interface{}{
		"order_id": orderID,
		"status":   status,
		"message":  message,
	})
}

// BroadcastOrderUpdateFull sends an order status update with additional details
// (e.g. delivery partner info) so the client can update its state without a
// round-trip to the server.
func (b *EventBroadcaster) BroadcastOrderUpdateFull(userID, orderID, status, message string, extra map[string]interface{}) {
	payload := map[string]interface{}{
		"order_id": orderID,
		"status":   status,
		"message":  message,
	}
	for k, v := range extra {
		payload[k] = v
	}
	b.sendToUser(userID, EventOrderUpdate, payload)
}

// BroadcastNewOrder notifies a restaurant partner about a new incoming order
func (b *EventBroadcaster) BroadcastNewOrder(restaurantOwnerID, orderID string, orderSummary map[string]interface{}) {
	b.sendToUser(restaurantOwnerID, EventNewOrder, map[string]interface{}{
		"order_id": orderID,
		"summary":  orderSummary,
	})
}

// BroadcastDeliveryRequest notifies a rider about a new delivery assignment
func (b *EventBroadcaster) BroadcastDeliveryRequest(riderID, orderID, restaurantID string, pickupLat, pickupLng float64) {
	b.sendToUser(riderID, EventDeliveryRequest, map[string]interface{}{
		"order_id":      orderID,
		"restaurant_id": restaurantID,
		"pickup_lat":    pickupLat,
		"pickup_lng":    pickupLng,
	})
}

// BroadcastDeliveryRequestFull notifies a rider with a fully enriched delivery request payload
// that matches the Flutter DeliveryRequest.fromMap() schema
func (b *EventBroadcaster) BroadcastDeliveryRequestFull(riderID string, payload map[string]interface{}) {
	b.sendToUser(riderID, EventDeliveryRequest, payload)
}

// BroadcastDeliveryLocation sends a rider's live location to the customer tracking this order
func (b *EventBroadcaster) BroadcastDeliveryLocation(customerID, orderID string, lat, lng float64, bearing float64) {
	b.sendToUser(customerID, EventDeliveryLocation, map[string]interface{}{
		"order_id": orderID,
		"lat":      lat,
		"lng":      lng,
		"bearing":  bearing,
	})
}

// BroadcastNotification sends a notification event to a user
func (b *EventBroadcaster) BroadcastNotification(userID, title, body, notifType string) {
	b.sendToUser(userID, EventNotification, map[string]interface{}{
		"title": title,
		"body":  body,
		"type":  notifType,
	})
}

// BroadcastRiderStatusChange notifies relevant parties when a rider's online status changes
func (b *EventBroadcaster) BroadcastRiderStatusChange(riderID string, isOnline bool) {
	b.sendToUser(riderID, EventRiderStatusChange, map[string]interface{}{
		"rider_id":  riderID,
		"is_online": isOnline,
	})
}

// BroadcastAll sends an event to all connected clients
func (b *EventBroadcaster) BroadcastAll(eventType EventType, payload interface{}) {
	evt := Event{
		Type:      eventType,
		Payload:   payload,
		Timestamp: time.Now().UTC().Format(time.RFC3339),
	}
	data, err := json.Marshal(evt)
	if err != nil {
		log.Printf("[ws] BroadcastAll marshal error: %v", err)
		return
	}
	b.hub.broadcast <- data
}

// sendToUser marshals an event and sends it to a specific user
func (b *EventBroadcaster) sendToUser(userID string, eventType EventType, payload interface{}) {
	evt := Event{
		Type:      eventType,
		Payload:   payload,
		Timestamp: time.Now().UTC().Format(time.RFC3339),
	}
	data, err := json.Marshal(evt)
	if err != nil {
		log.Printf("[ws] sendToUser marshal error for %s: %v", userID, err)
		return
	}
	b.hub.SendToUser(userID, data)
}
