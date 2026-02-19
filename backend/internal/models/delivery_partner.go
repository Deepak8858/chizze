package models

import "time"

// DeliveryPartner represents a delivery driver
type DeliveryPartner struct {
	ID                 string    `json:"$id"`
	UserID             string    `json:"user_id"`
	VehicleType        string    `json:"vehicle_type"` // bike | scooter | bicycle | car
	VehicleNumber      string    `json:"vehicle_number"`
	LicenseNumber      string    `json:"license_number"`
	IsOnline           bool      `json:"is_online"`
	IsOnDelivery       bool      `json:"is_on_delivery"`
	CurrentLatitude    float64   `json:"current_latitude"`
	CurrentLongitude   float64   `json:"current_longitude"`
	LastLocationUpdate time.Time `json:"last_location_update"`
	Rating             float64   `json:"rating"`
	TotalRatings       int       `json:"total_ratings"`
	TotalDeliveries    int       `json:"total_deliveries"`
	TotalEarnings      float64   `json:"total_earnings"`
	BankAccountID      string    `json:"bank_account_id"`
	DocumentsVerified  bool      `json:"documents_verified"`
	CreatedAt          time.Time `json:"created_at"`
	UpdatedAt          time.Time `json:"updated_at"`
}

// DeliveryLocation for real-time tracking
type DeliveryLocation struct {
	ID        string    `json:"$id"`
	OrderID   string    `json:"order_id"`
	PartnerID string    `json:"partner_id"`
	Latitude  float64   `json:"latitude"`
	Longitude float64   `json:"longitude"`
	Heading   float64   `json:"heading"`
	Speed     float64   `json:"speed"`
	Timestamp time.Time `json:"timestamp"`
}

// UpdateLocationRequest for partner location push
type UpdateLocationRequest struct {
	Latitude  float64 `json:"latitude" binding:"required"`
	Longitude float64 `json:"longitude" binding:"required"`
	Heading   float64 `json:"heading"`
	Speed     float64 `json:"speed"`
}
