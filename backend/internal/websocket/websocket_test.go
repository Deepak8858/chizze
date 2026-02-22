package websocket

import (
	"encoding/json"
	"testing"
	"time"
)

func TestNewHub(t *testing.T) {
	hub := NewHub()
	if hub == nil {
		t.Fatal("NewHub() should not return nil")
	}
	if hub.clients == nil {
		t.Error("clients map should be initialized")
	}
	if hub.broadcast == nil {
		t.Error("broadcast channel should be initialized")
	}
	if hub.register == nil {
		t.Error("register channel should be initialized")
	}
	if hub.unregister == nil {
		t.Error("unregister channel should be initialized")
	}
}

func TestHub_RegisterUnregister(t *testing.T) {
	hub := NewHub()
	go hub.Run()

	client := &Client{
		hub:    hub,
		UserID: "user_1",
		send:   make(chan []byte, 256),
	}

	// Register
	hub.register <- client
	time.Sleep(50 * time.Millisecond) // let goroutine process

	hub.mu.RLock()
	if _, ok := hub.clients[client]; !ok {
		t.Error("Client should be registered")
	}
	hub.mu.RUnlock()

	// Unregister
	hub.unregister <- client
	time.Sleep(50 * time.Millisecond)

	hub.mu.RLock()
	if _, ok := hub.clients[client]; ok {
		t.Error("Client should be unregistered")
	}
	hub.mu.RUnlock()
}

func TestHub_SendToUser(t *testing.T) {
	hub := NewHub()
	go hub.Run()

	client1 := &Client{hub: hub, UserID: "user_1", send: make(chan []byte, 256)}
	client2 := &Client{hub: hub, UserID: "user_2", send: make(chan []byte, 256)}

	hub.register <- client1
	hub.register <- client2
	time.Sleep(50 * time.Millisecond)

	// Send to user_1 only
	hub.SendToUser("user_1", []byte("hello user 1"))

	select {
	case msg := <-client1.send:
		if string(msg) != "hello user 1" {
			t.Errorf("Expected 'hello user 1', got %q", string(msg))
		}
	case <-time.After(100 * time.Millisecond):
		t.Error("user_1 should have received a message")
	}

	// user_2 should NOT receive anything
	select {
	case msg := <-client2.send:
		t.Errorf("user_2 should not have received message, got %q", string(msg))
	case <-time.After(50 * time.Millisecond):
		// expected
	}
}

func TestHub_Broadcast(t *testing.T) {
	hub := NewHub()
	go hub.Run()

	client1 := &Client{hub: hub, UserID: "user_1", send: make(chan []byte, 256)}
	client2 := &Client{hub: hub, UserID: "user_2", send: make(chan []byte, 256)}

	hub.register <- client1
	hub.register <- client2
	time.Sleep(50 * time.Millisecond)

	hub.broadcast <- []byte("broadcast msg")
	time.Sleep(50 * time.Millisecond)

	for _, c := range []*Client{client1, client2} {
		select {
		case msg := <-c.send:
			if string(msg) != "broadcast msg" {
				t.Errorf("Expected 'broadcast msg', got %q", string(msg))
			}
		case <-time.After(100 * time.Millisecond):
			t.Errorf("Client %s should have received broadcast", c.UserID)
		}
	}
}

func TestHub_SendToUser_NonExistent(t *testing.T) {
	hub := NewHub()
	go hub.Run()

	time.Sleep(20 * time.Millisecond)

	// Should not panic when user doesn't exist
	hub.SendToUser("non_existent", []byte("hello"))
}

// ─── Events Tests ───

func TestEventType_Constants(t *testing.T) {
	// Ensure event type constants have expected values
	checks := map[EventType]string{
		EventOrderUpdate:       "order_update",
		EventDeliveryRequest:   "delivery_request",
		EventDeliveryLocation:  "delivery_location",
		EventNewOrder:          "new_order",
		EventNotification:      "notification",
		EventRiderStatusChange: "rider_status_change",
		EventRestaurantUpdate:  "restaurant_update",
	}

	for got, expected := range checks {
		if string(got) != expected {
			t.Errorf("Expected %q, got %q", expected, string(got))
		}
	}
}

func TestEvent_JSON_Serialization(t *testing.T) {
	evt := Event{
		Type:      EventOrderUpdate,
		Payload:   map[string]string{"order_id": "123", "status": "confirmed"},
		Timestamp: "2025-01-01T00:00:00Z",
	}

	data, err := json.Marshal(evt)
	if err != nil {
		t.Fatalf("Marshal error: %v", err)
	}

	var decoded Event
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("Unmarshal error: %v", err)
	}

	if decoded.Type != EventOrderUpdate {
		t.Errorf("Type = %q, want %q", decoded.Type, EventOrderUpdate)
	}
	if decoded.Timestamp != "2025-01-01T00:00:00Z" {
		t.Errorf("Timestamp = %q, want %q", decoded.Timestamp, "2025-01-01T00:00:00Z")
	}
}

func TestNewEventBroadcaster(t *testing.T) {
	hub := NewHub()
	b := NewEventBroadcaster(hub)
	if b == nil {
		t.Fatal("NewEventBroadcaster should not return nil")
	}
	if b.hub != hub {
		t.Error("EventBroadcaster.hub should reference the provided hub")
	}
}

func TestEventBroadcaster_BroadcastOrderUpdate(t *testing.T) {
	hub := NewHub()
	go hub.Run()

	client := &Client{hub: hub, UserID: "customer_1", send: make(chan []byte, 256)}
	hub.register <- client
	time.Sleep(50 * time.Millisecond)

	b := NewEventBroadcaster(hub)
	b.BroadcastOrderUpdate("customer_1", "order_123", "confirmed", "Your order is confirmed")

	select {
	case msg := <-client.send:
		var evt Event
		if err := json.Unmarshal(msg, &evt); err != nil {
			t.Fatalf("Failed to unmarshal event: %v", err)
		}
		if evt.Type != EventOrderUpdate {
			t.Errorf("Event type = %q, want %q", evt.Type, EventOrderUpdate)
		}
		payload := evt.Payload.(map[string]interface{})
		if payload["order_id"] != "order_123" {
			t.Errorf("order_id = %v, want 'order_123'", payload["order_id"])
		}
		if payload["status"] != "confirmed" {
			t.Errorf("status = %v, want 'confirmed'", payload["status"])
		}
	case <-time.After(200 * time.Millisecond):
		t.Error("Should have received order update event")
	}
}

func TestEventBroadcaster_BroadcastDeliveryRequest(t *testing.T) {
	hub := NewHub()
	go hub.Run()

	client := &Client{hub: hub, UserID: "rider_1", send: make(chan []byte, 256)}
	hub.register <- client
	time.Sleep(50 * time.Millisecond)

	b := NewEventBroadcaster(hub)
	b.BroadcastDeliveryRequest("rider_1", "order_456", "rest_789", 12.97, 77.59)

	select {
	case msg := <-client.send:
		var evt Event
		if err := json.Unmarshal(msg, &evt); err != nil {
			t.Fatalf("Failed to unmarshal: %v", err)
		}
		if evt.Type != EventDeliveryRequest {
			t.Errorf("Type = %q, want %q", evt.Type, EventDeliveryRequest)
		}
		payload := evt.Payload.(map[string]interface{})
		if payload["order_id"] != "order_456" {
			t.Errorf("order_id = %v", payload["order_id"])
		}
	case <-time.After(200 * time.Millisecond):
		t.Error("Should have received delivery request event")
	}
}

func TestEventBroadcaster_BroadcastNotification(t *testing.T) {
	hub := NewHub()
	go hub.Run()

	client := &Client{hub: hub, UserID: "user_1", send: make(chan []byte, 256)}
	hub.register <- client
	time.Sleep(50 * time.Millisecond)

	b := NewEventBroadcaster(hub)
	b.BroadcastNotification("user_1", "Order Ready", "Your order is ready for pickup", "order")

	select {
	case msg := <-client.send:
		var evt Event
		if err := json.Unmarshal(msg, &evt); err != nil {
			t.Fatalf("Failed to unmarshal: %v", err)
		}
		if evt.Type != EventNotification {
			t.Errorf("Type = %q, want %q", evt.Type, EventNotification)
		}
		payload := evt.Payload.(map[string]interface{})
		if payload["title"] != "Order Ready" {
			t.Errorf("title = %v", payload["title"])
		}
	case <-time.After(200 * time.Millisecond):
		t.Error("Should have received notification event")
	}
}
