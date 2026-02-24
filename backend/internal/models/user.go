package models

// User represents a Chizze user profile (matches Appwrite users collection)
type User struct {
	ID               string  `json:"$id"`
	Name             string  `json:"name"`
	Email            string  `json:"email"`
	Phone            string  `json:"phone"`
	AvatarURL        string  `json:"avatar_url"`
	Role             string  `json:"role"` // customer | restaurant_owner | delivery_partner | admin
	DefaultAddressID string  `json:"default_address_id"`
	IsVeg            bool    `json:"is_veg"`
	DarkMode         bool    `json:"dark_mode"`
	IsGoldMember     bool    `json:"is_gold_member"`
	ReferralCode     string  `json:"referral_code"`
	ReferredBy       string  `json:"referred_by"`
	FCMToken         string  `json:"fcm_token"`
	Address          string  `json:"address"`
	Latitude         float64 `json:"latitude"`
	Longitude        float64 `json:"longitude"`
}

// Address is a saved delivery address (matches Appwrite addresses collection)
type Address struct {
	ID          string  `json:"$id"`
	UserID      string  `json:"user_id"`
	Label       string  `json:"label"` // home | work | other
	FullAddress string  `json:"full_address"`
	Landmark    string  `json:"landmark"`
	Latitude    float64 `json:"latitude"`
	Longitude   float64 `json:"longitude"`
	IsDefault   bool    `json:"is_default"`
}

// UpdateProfileRequest is the body for PUT /users/me
type UpdateProfileRequest struct {
	Name  string `json:"name"`
	Email string `json:"email"`
}

// CreateAddressRequest is the body for POST /users/me/addresses
type CreateAddressRequest struct {
	Label       string  `json:"label" binding:"required"`
	FullAddress string  `json:"full_address" binding:"required"`
	Landmark    string  `json:"landmark"`
	Latitude    float64 `json:"latitude"`
	Longitude   float64 `json:"longitude"`
	IsDefault   bool    `json:"is_default"`
}
