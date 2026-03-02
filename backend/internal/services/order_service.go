package services

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"math"
	"time"

	"github.com/chizze/backend/internal/models"
)

// OrderService handles order business logic
type OrderService struct {
	appwrite *AppwriteService
}

// NewOrderService creates an order service
func NewOrderService(aw *AppwriteService) *OrderService {
	return &OrderService{appwrite: aw}
}

// GenerateOrderNumber creates a unique order number using timestamp + random bytes
func (s *OrderService) GenerateOrderNumber() string {
	b := make([]byte, 3)
	rand.Read(b)
	suffix := hex.EncodeToString(b) // 6 hex chars
	return fmt.Sprintf("CHZ-%d-%s", time.Now().UnixMilli()%1000000, suffix)
}

// CalculateFees computes delivery fee, platform fee, and GST.
// deliveryType "eco" waives the delivery fee for the customer.
func (s *OrderService) CalculateFees(itemTotal float64, distanceKm float64, deliveryType string) (deliveryFee, platformFee, gst float64) {
	// Eco delivery: free delivery fee for the customer
	if deliveryType == "eco" {
		deliveryFee = 0
	} else if itemTotal >= 299 {
		// Standard delivery: free above ₹299, else distance-based
		deliveryFee = 0
	} else {
		deliveryFee = math.Ceil(distanceKm * 8) // ₹8/km
		if deliveryFee < 20 {
			deliveryFee = 20
		}
		if deliveryFee > 80 {
			deliveryFee = 80
		}
	}

	// Platform fee: flat ₹5
	platformFee = 5.0

	// GST: 5% on food items
	gst = math.Round(itemTotal*0.05*100) / 100

	return
}

// ValidateTransition checks if order status change is allowed
func (s *OrderService) ValidateTransition(from, to string) error {
	if !models.CanTransition(from, to) {
		return fmt.Errorf("invalid transition from '%s' to '%s'", from, to)
	}
	return nil
}
