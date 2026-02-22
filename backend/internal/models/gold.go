package models

import "time"

// GoldSubscription represents a Chizze Gold membership
type GoldSubscription struct {
	ID        string    `json:"$id"`
	UserID    string    `json:"user_id"`
	PlanType  string    `json:"plan_type"`  // monthly | quarterly | annual
	Status    string    `json:"status"`     // active | expired | cancelled
	StartDate time.Time `json:"start_date"`
	EndDate   time.Time `json:"end_date"`
	Amount    float64   `json:"amount"`
	PaymentID string    `json:"payment_id"`
	CreatedAt time.Time `json:"created_at"`
}

// GoldPlan represents available subscription plans
type GoldPlan struct {
	Type         string  `json:"type"` // monthly | quarterly | annual
	Price        float64 `json:"price"`
	OriginalPrice float64 `json:"original_price"`
	Label        string  `json:"label"`
	Description  string  `json:"description"`
	SavePercent  int     `json:"save_percent"`
}

// SubscribeGoldRequest is the body for POST /gold/subscribe
type SubscribeGoldRequest struct {
	PlanType  string `json:"plan_type" binding:"required"`
	PaymentID string `json:"payment_id" binding:"required"`
}

// GoldPlans returns the available subscription plans
func GoldPlans() []GoldPlan {
	return []GoldPlan{
		{
			Type:          "monthly",
			Price:         149,
			OriginalPrice: 149,
			Label:         "1 Month",
			Description:   "Free delivery + exclusive offers",
			SavePercent:   0,
		},
		{
			Type:          "quarterly",
			Price:         349,
			OriginalPrice: 447,
			Label:         "3 Months",
			Description:   "Save 22% vs monthly",
			SavePercent:   22,
		},
		{
			Type:          "annual",
			Price:         999,
			OriginalPrice: 1788,
			Label:         "12 Months",
			Description:   "Best value — save 44%",
			SavePercent:   44,
		},
	}
}
