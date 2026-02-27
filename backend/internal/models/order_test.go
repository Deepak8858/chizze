package models

import "testing"

func TestCanTransition_ValidTransitions(t *testing.T) {
	validCases := []struct {
		from string
		to   string
	}{
		{OrderStatusPlaced, OrderStatusConfirmed},
		{OrderStatusPlaced, OrderStatusCancelled},
		{OrderStatusConfirmed, OrderStatusPreparing},
		{OrderStatusConfirmed, OrderStatusCancelled},
		{OrderStatusPreparing, OrderStatusReady},
		{OrderStatusPreparing, OrderStatusCancelled},
		{OrderStatusReady, OrderStatusPickedUp},
		{OrderStatusPickedUp, OrderStatusOutForDelivery},
		{OrderStatusOutForDelivery, OrderStatusDelivered},
	}

	for _, tc := range validCases {
		t.Run(tc.from+"→"+tc.to, func(t *testing.T) {
			if !CanTransition(tc.from, tc.to) {
				t.Errorf("CanTransition(%q, %q) should be true", tc.from, tc.to)
			}
		})
	}
}

func TestCanTransition_InvalidTransitions(t *testing.T) {
	invalidCases := []struct {
		from string
		to   string
	}{
		// Skip statuses
		{OrderStatusPlaced, OrderStatusReady},
		{OrderStatusPlaced, OrderStatusDelivered},
		{OrderStatusConfirmed, OrderStatusDelivered},
		// Backward transitions
		{OrderStatusDelivered, OrderStatusPlaced},
		{OrderStatusReady, OrderStatusPreparing},
		{OrderStatusPreparing, OrderStatusConfirmed},
		// Terminal states (delivered has no transitions)
		{OrderStatusDelivered, OrderStatusCancelled},
		{OrderStatusCancelled, OrderStatusPlaced},
		// Cannot cancel after ready
		{OrderStatusReady, OrderStatusCancelled},
		{OrderStatusPickedUp, OrderStatusCancelled},
		{OrderStatusOutForDelivery, OrderStatusCancelled},
		// Same status
		{OrderStatusPlaced, OrderStatusPlaced},
		// Unknown statuses
		{"unknown", OrderStatusPlaced},
		{OrderStatusPlaced, "unknown"},
		{"", ""},
	}

	for _, tc := range invalidCases {
		t.Run(tc.from+"→"+tc.to, func(t *testing.T) {
			if CanTransition(tc.from, tc.to) {
				t.Errorf("CanTransition(%q, %q) should be false", tc.from, tc.to)
			}
		})
	}
}

func TestValidOrderTransitions_Coverage(t *testing.T) {
	// Ensure all expected statuses that have outgoing transitions are in the map
	expectedFrom := []string{
		OrderStatusPlaced,
		OrderStatusConfirmed,
		OrderStatusPreparing,
		OrderStatusReady,
		OrderStatusPickedUp,
		OrderStatusOutForDelivery,
	}

	for _, status := range expectedFrom {
		if _, ok := ValidOrderTransitions[status]; !ok {
			t.Errorf("ValidOrderTransitions missing key %q", status)
		}
	}

	// Terminal states should NOT be in the transition map
	terminalStatuses := []string{OrderStatusDelivered, OrderStatusCancelled}
	for _, status := range terminalStatuses {
		if _, ok := ValidOrderTransitions[status]; ok {
			t.Errorf("Terminal status %q should not have outgoing transitions", status)
		}
	}
}

func TestOrderConstants(t *testing.T) {
	// Verify constants have expected values (guards against refactoring mistakes)
	checks := map[string]string{
		"placed":           OrderStatusPlaced,
		"confirmed":        OrderStatusConfirmed,
		"preparing":        OrderStatusPreparing,
		"ready":            OrderStatusReady,
		"pickedUp":        OrderStatusPickedUp,
		"outForDelivery": OrderStatusOutForDelivery,
		"delivered":        OrderStatusDelivered,
		"cancelled":        OrderStatusCancelled,
	}

	for expected, got := range checks {
		if got != expected {
			t.Errorf("Expected %q, got %q", expected, got)
		}
	}
}
