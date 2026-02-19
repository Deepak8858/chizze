package models

import "time"

// Order status constants
const (
	OrderStatusPlaced         = "placed"
	OrderStatusConfirmed      = "confirmed"
	OrderStatusPreparing      = "preparing"
	OrderStatusReady          = "ready"
	OrderStatusPickedUp       = "picked_up"
	OrderStatusOutForDelivery = "out_for_delivery"
	OrderStatusDelivered      = "delivered"
	OrderStatusCancelled      = "cancelled"
)

// Payment status constants
const (
	PaymentPending  = "pending"
	PaymentPaid     = "paid"
	PaymentRefunded = "refunded"
	PaymentFailed   = "failed"
)

// Order represents a food order
type Order struct {
	ID                      string     `json:"$id"`
	OrderNumber             string     `json:"order_number"`
	CustomerID              string     `json:"customer_id"`
	RestaurantID            string     `json:"restaurant_id"`
	DeliveryPartnerID       string     `json:"delivery_partner_id,omitempty"`
	DeliveryAddressID       string     `json:"delivery_address_id"`
	DeliveryAddressSnapshot string     `json:"delivery_address_snapshot"`
	Items                   string     `json:"items"` // JSON array string
	ItemTotal               float64    `json:"item_total"`
	DeliveryFee             float64    `json:"delivery_fee"`
	PlatformFee             float64    `json:"platform_fee"`
	GST                     float64    `json:"gst"`
	Discount                float64    `json:"discount"`
	CouponCode              string     `json:"coupon_code,omitempty"`
	Tip                     float64    `json:"tip"`
	GrandTotal              float64    `json:"grand_total"`
	PaymentMethod           string     `json:"payment_method"`
	PaymentStatus           string     `json:"payment_status"`
	PaymentID               string     `json:"payment_id,omitempty"`
	Status                  string     `json:"status"`
	SpecialInstructions     string     `json:"special_instructions"`
	DeliveryInstructions    string     `json:"delivery_instructions"`
	EstimatedDeliveryMin    int        `json:"estimated_delivery_min"`
	PlacedAt                time.Time  `json:"placed_at"`
	ConfirmedAt             *time.Time `json:"confirmed_at,omitempty"`
	PreparedAt              *time.Time `json:"prepared_at,omitempty"`
	PickedUpAt              *time.Time `json:"picked_up_at,omitempty"`
	DeliveredAt             *time.Time `json:"delivered_at,omitempty"`
	CancelledAt             *time.Time `json:"cancelled_at,omitempty"`
	CancellationReason      string     `json:"cancellation_reason,omitempty"`
	CancelledBy             string     `json:"cancelled_by,omitempty"`
	CreatedAt               time.Time  `json:"created_at"`
	UpdatedAt               time.Time  `json:"updated_at"`
}

// OrderItem is a line item in an order
type OrderItem struct {
	ItemID         string  `json:"item_id"`
	Name           string  `json:"name"`
	Quantity       int     `json:"quantity"`
	Price          float64 `json:"price"`
	IsVeg          bool    `json:"is_veg"`
	Customizations string  `json:"customizations,omitempty"`
}

// PlaceOrderRequest for POST /orders
type PlaceOrderRequest struct {
	RestaurantID         string      `json:"restaurant_id" binding:"required"`
	DeliveryAddressID    string      `json:"delivery_address_id" binding:"required"`
	Items                []OrderItem `json:"items" binding:"required,min=1"`
	PaymentMethod        string      `json:"payment_method" binding:"required"`
	CouponCode           string      `json:"coupon_code"`
	Tip                  float64     `json:"tip"`
	SpecialInstructions  string      `json:"special_instructions"`
	DeliveryInstructions string      `json:"delivery_instructions"`
}

// CancelOrderRequest for PUT /orders/:id/cancel
type CancelOrderRequest struct {
	Reason string `json:"reason" binding:"required"`
}

// ValidOrderTransitions defines allowed status transitions
var ValidOrderTransitions = map[string][]string{
	OrderStatusPlaced:         {OrderStatusConfirmed, OrderStatusCancelled},
	OrderStatusConfirmed:      {OrderStatusPreparing, OrderStatusCancelled},
	OrderStatusPreparing:      {OrderStatusReady, OrderStatusCancelled},
	OrderStatusReady:          {OrderStatusPickedUp},
	OrderStatusPickedUp:       {OrderStatusOutForDelivery},
	OrderStatusOutForDelivery: {OrderStatusDelivered},
}

// CanTransition checks if a status transition is valid
func CanTransition(from, to string) bool {
	allowed, ok := ValidOrderTransitions[from]
	if !ok {
		return false
	}
	for _, s := range allowed {
		if s == to {
			return true
		}
	}
	return false
}
