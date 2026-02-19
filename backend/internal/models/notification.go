package models

// Notification represents an in-app notification
type Notification struct {
	ID        string `json:"$id"`
	UserID    string `json:"user_id"`
	Type      string `json:"type"` // order_update | promo | system | review
	Title     string `json:"title"`
	Body      string `json:"body"`
	Data      string `json:"data"` // JSON: {order_id, restaurant_id, ...}
	IsRead    bool   `json:"is_read"`
	CreatedAt string `json:"created_at"`
}
