package services

import (
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

// GenerateOrderNumber creates a unique order number
func (s *OrderService) GenerateOrderNumber() string {
	return fmt.Sprintf("CHZ-%d", time.Now().UnixMilli()%1000000)
}

// CalculateFees computes delivery fee, platform fee, and GST
func (s *OrderService) CalculateFees(itemTotal float64, distanceKm float64) (deliveryFee, platformFee, gst float64) {
	// Delivery fee: free above ₹299, else distance-based
	if itemTotal >= 299 {
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
