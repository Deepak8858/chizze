package models

import "time"

// User represents a Chizze user profile
type User struct {
	ID                 string    `json:"$id"`
	Name               string    `json:"name"`
	Email              string    `json:"email"`
	Phone              string    `json:"phone"`
	AvatarURL          string    `json:"avatar_url"`
	Role               string    `json:"role"` // customer | restaurant_owner | delivery_partner | admin
	IsGoldMember       bool      `json:"is_gold_member"`
	DietaryPreferences []string  `json:"dietary_preferences"`
	Allergens          []string  `json:"allergens"`
	ReferralCode       string    `json:"referral_code"`
	ReferredBy         string    `json:"referred_by"`
	FCMToken           string    `json:"fcm_token"`
	CreatedAt          time.Time `json:"created_at"`
	UpdatedAt          time.Time `json:"updated_at"`
}

// Address is a saved delivery address
type Address struct {
	ID           string  `json:"$id"`
	UserID       string  `json:"user_id"`
	Label        string  `json:"label"` // home | work | other
	AddressLine1 string  `json:"address_line_1"`
	AddressLine2 string  `json:"address_line_2"`
	Landmark     string  `json:"landmark"`
	City         string  `json:"city"`
	State        string  `json:"state"`
	Pincode      string  `json:"pincode"`
	Latitude     float64 `json:"latitude"`
	Longitude    float64 `json:"longitude"`
	IsDefault    bool    `json:"is_default"`
	CreatedAt    string  `json:"created_at"`
}

// UpdateProfileRequest is the body for PUT /users/me
type UpdateProfileRequest struct {
	Name               string   `json:"name"`
	Email              string   `json:"email"`
	DietaryPreferences []string `json:"dietary_preferences"`
	Allergens          []string `json:"allergens"`
}

// CreateAddressRequest is the body for POST /users/me/addresses
type CreateAddressRequest struct {
	Label        string  `json:"label" binding:"required"`
	AddressLine1 string  `json:"address_line_1" binding:"required"`
	AddressLine2 string  `json:"address_line_2"`
	Landmark     string  `json:"landmark"`
	City         string  `json:"city" binding:"required"`
	State        string  `json:"state"`
	Pincode      string  `json:"pincode" binding:"required"`
	Latitude     float64 `json:"latitude"`
	Longitude    float64 `json:"longitude"`
	IsDefault    bool    `json:"is_default"`
}
