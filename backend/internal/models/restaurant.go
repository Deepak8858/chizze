package models

import "time"

// Restaurant represents a restaurant listing
type Restaurant struct {
	ID                 string    `json:"$id"`
	OwnerID            string    `json:"owner_id"`
	Name               string    `json:"name"`
	Description        string    `json:"description"`
	CoverImageURL      string    `json:"cover_image_url"`
	LogoURL            string    `json:"logo_url"`
	Cuisines           []string  `json:"cuisines"`
	Address            string    `json:"address"`
	Latitude           float64   `json:"latitude"`
	Longitude          float64   `json:"longitude"`
	City               string    `json:"city"`
	Rating             float64   `json:"rating"`
	TotalRatings       int       `json:"total_ratings"`
	PriceForTwo        int       `json:"price_for_two"`
	AvgDeliveryTimeMin int       `json:"avg_delivery_time_min"`
	IsVegOnly          bool      `json:"is_veg_only"`
	IsOnline           bool      `json:"is_online"`
	IsFeatured         bool      `json:"is_featured"`
	IsPromoted         bool      `json:"is_promoted"`
	OpeningTime        string    `json:"opening_time"`
	ClosingTime        string    `json:"closing_time"`
	FSSAILicense       string    `json:"fssai_license"`
	GSTNumber          string    `json:"gst_number"`
	Commission         float64   `json:"commission_percentage"`
	CreatedAt          time.Time `json:"created_at"`
	UpdatedAt          time.Time `json:"updated_at"`
}

// MenuCategory groups menu items
type MenuCategory struct {
	ID           string `json:"$id"`
	RestaurantID string `json:"restaurant_id"`
	Name         string `json:"name"`
	SortOrder    int    `json:"sort_order"`
	IsActive     bool   `json:"is_active"`
}

// MenuItem is a single dish
type MenuItem struct {
	ID              string   `json:"$id"`
	RestaurantID    string   `json:"restaurant_id"`
	CategoryID      string   `json:"category_id"`
	Name            string   `json:"name"`
	Description     string   `json:"description"`
	Price           float64  `json:"price"`
	ImageURL        string   `json:"image_url"`
	IsVeg           bool     `json:"is_veg"`
	IsAvailable     bool     `json:"is_available"`
	IsBestseller    bool     `json:"is_bestseller"`
	IsMustTry       bool     `json:"is_must_try"`
	SpiceLevel      string   `json:"spice_level"` // mild | medium | spicy
	PrepTimeMin     int      `json:"preparation_time_min"`
	Customizations  string   `json:"customizations"` // JSON string
	Calories        int      `json:"calories"`
	Allergens       []string `json:"allergens"`
	SortOrder       int      `json:"sort_order"`
	CreatedAt       string   `json:"created_at"`
	UpdatedAt       string   `json:"updated_at"`
}

// CreateMenuItemRequest for POST /partner/menu
type CreateMenuItemRequest struct {
	CategoryID  string  `json:"category_id" binding:"required"`
	Name        string  `json:"name" binding:"required"`
	Description string  `json:"description"`
	Price       float64 `json:"price" binding:"required,gt=0"`
	IsVeg       bool    `json:"is_veg"`
	SpiceLevel  string  `json:"spice_level"`
	PrepTimeMin int     `json:"preparation_time_min"`
}
