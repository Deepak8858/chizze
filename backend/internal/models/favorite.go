package models

import "time"

// Favorite represents a user's favorited restaurant
type Favorite struct {
	ID           string    `json:"$id"`
	UserID       string    `json:"user_id"`
	RestaurantID string    `json:"restaurant_id"`
	CreatedAt    time.Time `json:"created_at"`
}

// CreateFavoriteRequest is the body for POST /users/me/favorites
type CreateFavoriteRequest struct {
	RestaurantID string `json:"restaurant_id" binding:"required"`
}
