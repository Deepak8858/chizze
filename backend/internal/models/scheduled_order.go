package models

import "time"

// ScheduledOrder represents a pre-scheduled order for future delivery
type ScheduledOrder struct {
	ID            string    `json:"$id"`
	UserID        string    `json:"user_id"`
	RestaurantID  string    `json:"restaurant_id"`
	Items         []byte    `json:"items"` // JSON-encoded cart items
	ScheduledFor  time.Time `json:"scheduled_for"`
	Status        string    `json:"status"` // scheduled | processing | completed | cancelled
	OrderID       string    `json:"order_id"` // linked order once placed
	AddressID     string    `json:"address_id"`
	CouponCode    string    `json:"coupon_code"`
	CreatedAt     time.Time `json:"created_at"`
}

// CreateScheduledOrderRequest is the body for POST /orders/schedule
type CreateScheduledOrderRequest struct {
	RestaurantID string `json:"restaurant_id" binding:"required"`
	Items        []struct {
		MenuItemID     string                 `json:"menu_item_id"`
		Quantity       int                    `json:"quantity"`
		Customizations map[string]interface{} `json:"customizations"`
	} `json:"items" binding:"required"`
	ScheduledFor string `json:"scheduled_for" binding:"required"` // ISO 8601
	AddressID    string `json:"address_id" binding:"required"`
	CouponCode   string `json:"coupon_code"`
}
