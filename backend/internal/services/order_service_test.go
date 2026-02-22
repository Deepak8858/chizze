package services

import (
	"math"
	"strings"
	"testing"
)

func TestOrderService_GenerateOrderNumber(t *testing.T) {
	svc := &OrderService{}

	num := svc.GenerateOrderNumber()

	// Must start with "CHZ-"
	if !strings.HasPrefix(num, "CHZ-") {
		t.Errorf("Order number should start with 'CHZ-', got %q", num)
	}

	// Must contain two dashes (CHZ-timestamp-hex)
	parts := strings.Split(num, "-")
	if len(parts) != 3 {
		t.Errorf("Expected 3 parts (CHZ-timestamp-hex), got %d: %q", len(parts), num)
	}

	// Random suffix should be 6 hex chars
	if len(parts) == 3 && len(parts[2]) != 6 {
		t.Errorf("Hex suffix should be 6 chars, got %d: %q", len(parts[2]), parts[2])
	}
}

func TestOrderService_GenerateOrderNumber_Uniqueness(t *testing.T) {
	svc := &OrderService{}
	seen := make(map[string]bool)
	for i := 0; i < 100; i++ {
		num := svc.GenerateOrderNumber()
		if seen[num] {
			t.Errorf("Duplicate order number: %q", num)
		}
		seen[num] = true
	}
}

func TestOrderService_CalculateFees_FreeDelivery(t *testing.T) {
	svc := &OrderService{}

	// Above ₹299 → free delivery
	deliveryFee, platformFee, gst := svc.CalculateFees(300, 10)
	if deliveryFee != 0 {
		t.Errorf("Delivery fee should be 0 for ₹300 order, got %.2f", deliveryFee)
	}
	if platformFee != 5 {
		t.Errorf("Platform fee should be ₹5, got %.2f", platformFee)
	}
	expectedGST := math.Round(300*0.05*100) / 100
	if gst != expectedGST {
		t.Errorf("GST should be %.2f, got %.2f", expectedGST, gst)
	}

	// Exactly ₹299 → free delivery
	deliveryFee, _, _ = svc.CalculateFees(299, 5)
	if deliveryFee != 0 {
		t.Errorf("Delivery fee should be 0 at ₹299, got %.2f", deliveryFee)
	}
}

func TestOrderService_CalculateFees_PaidDelivery(t *testing.T) {
	svc := &OrderService{}

	tests := []struct {
		name          string
		itemTotal     float64
		distanceKm    float64
		wantDelivery  float64
	}{
		{"₹8/km normal", 100, 5, 40},         // 5 * 8 = 40
		{"min ₹20", 100, 1, 20},               // 1 * 8 = 8 → clamped to 20
		{"max ₹80", 100, 15, 80},              // 15 * 8 = 120 → clamped to 80
		{"zero distance min", 100, 0, 20},      // 0 * 8 = 0 → clamped to 20
		{"₹298 just under threshold", 298, 5, 40},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			deliveryFee, _, _ := svc.CalculateFees(tc.itemTotal, tc.distanceKm)
			if deliveryFee != tc.wantDelivery {
				t.Errorf("deliveryFee = %.2f, want %.2f", deliveryFee, tc.wantDelivery)
			}
		})
	}
}

func TestOrderService_CalculateFees_GST(t *testing.T) {
	svc := &OrderService{}

	tests := []struct {
		name      string
		itemTotal float64
		wantGST   float64
	}{
		{"₹100", 100, 5.0},
		{"₹250", 250, 12.5},
		{"₹1", 1, 0.05},
		{"₹0", 0, 0},
		{"₹999.99", 999.99, 50.0},  // 999.99 * 0.05 = 49.9995 → rounds to 50.0
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			_, _, gst := svc.CalculateFees(tc.itemTotal, 5)
			if gst != tc.wantGST {
				t.Errorf("GST = %.2f, want %.2f", gst, tc.wantGST)
			}
		})
	}
}

func TestOrderService_CalculateFees_PlatformFeeAlwaysFive(t *testing.T) {
	svc := &OrderService{}
	amounts := []float64{0, 100, 299, 300, 500, 1000}
	for _, amt := range amounts {
		_, platformFee, _ := svc.CalculateFees(amt, 5)
		if platformFee != 5 {
			t.Errorf("Platform fee should always be ₹5 for amount %.2f, got %.2f", amt, platformFee)
		}
	}
}

func TestOrderService_ValidateTransition(t *testing.T) {
	svc := &OrderService{}

	// Valid transition
	if err := svc.ValidateTransition("placed", "confirmed"); err != nil {
		t.Errorf("Valid transition should not error: %v", err)
	}

	// Invalid transition
	if err := svc.ValidateTransition("placed", "delivered"); err == nil {
		t.Error("Invalid transition should return error")
	}

	// Check error message contains status names
	err := svc.ValidateTransition("placed", "delivered")
	if err != nil && !strings.Contains(err.Error(), "placed") {
		t.Errorf("Error message should contain 'placed': %v", err)
	}
}
