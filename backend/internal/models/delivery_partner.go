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

// DeliveryLocation for real-time tracking (matches Appwrite rider_locations collection)
type DeliveryLocation struct {
	ID        string  `json:"$id"`
	RiderID   string  `json:"rider_id"`
	Latitude  float64 `json:"latitude"`
	Longitude float64 `json:"longitude"`
	Heading   float64 `json:"heading"`
	Speed     float64 `json:"speed"`
	IsOnline  bool    `json:"is_online"`
}

// UpdateLocationRequest for partner location push
type UpdateLocationRequest struct {
	Latitude  float64 `json:"latitude" binding:"required"`
	Longitude float64 `json:"longitude" binding:"required"`
	Heading   float64 `json:"heading"`
	Speed     float64 `json:"speed"`
}

// Payout represents a delivery partner payout / withdrawal
type Payout struct {
	ID        string    `json:"$id"`
	PartnerID string    `json:"partner_id"`
	UserID    string    `json:"user_id"`
	Amount    float64   `json:"amount"`
	Status    string    `json:"status"` // pending | processing | completed | failed
	Method    string    `json:"method"` // bank_transfer | upi
	Reference string    `json:"reference"`
	Note      string    `json:"note"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// Payout status constants
const (
	PayoutStatusPending    = "pending"
	PayoutStatusProcessing = "processing"
	PayoutStatusCompleted  = "completed"
	PayoutStatusFailed     = "failed"
)

// RequestPayoutRequest is the DTO for payout requests
type RequestPayoutRequest struct {
	Amount float64 `json:"amount" binding:"required,gt=0"`
	Method string  `json:"method" binding:"required,oneof=bank_transfer upi"`
}

// UpdateDeliveryProfileRequest is the DTO for partner profile updates
type UpdateDeliveryProfileRequest struct {
	VehicleType   string `json:"vehicle_type"`
	VehicleNumber string `json:"vehicle_number"`
	BankAccountID string `json:"bank_account_id"`
}
