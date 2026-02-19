package models

import "time"

// Review is a customer review for an order
type Review struct {
	ID                string    `json:"$id"`
	OrderID           string    `json:"order_id"`
	CustomerID        string    `json:"customer_id"`
	RestaurantID      string    `json:"restaurant_id"`
	DeliveryPartnerID string    `json:"delivery_partner_id,omitempty"`
	FoodRating        int       `json:"food_rating"`     // 1-5
	DeliveryRating    int       `json:"delivery_rating"`  // 1-5
	ReviewText        string    `json:"review_text"`
	Tags              []string  `json:"tags"`
	Photos            []string  `json:"photos"`
	RestaurantReply   string    `json:"restaurant_reply,omitempty"`
	IsVisible         bool      `json:"is_visible"`
	CreatedAt         time.Time `json:"created_at"`
}

// CreateReviewRequest for POST /orders/:id/review
type CreateReviewRequest struct {
	FoodRating     int      `json:"food_rating" binding:"required,min=1,max=5"`
	DeliveryRating int      `json:"delivery_rating" binding:"required,min=1,max=5"`
	ReviewText     string   `json:"review_text"`
	Tags           []string `json:"tags"`
}

// ReplyReviewRequest for POST /partner/reviews/:id/reply
type ReplyReviewRequest struct {
	Reply string `json:"reply" binding:"required"`
}
