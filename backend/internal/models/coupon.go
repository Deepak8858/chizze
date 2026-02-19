package models

import "time"

// Coupon represents a discount coupon
type Coupon struct {
	ID            string    `json:"$id"`
	Code          string    `json:"code"`
	Description   string    `json:"description"`
	DiscountType  string    `json:"discount_type"` // percentage | flat
	DiscountValue float64   `json:"discount_value"`
	MaxDiscount   float64   `json:"max_discount"`
	MinOrderValue float64   `json:"min_order_value"`
	ValidFrom     time.Time `json:"valid_from"`
	ValidUntil    time.Time `json:"valid_until"`
	UsageLimit    int       `json:"usage_limit"`
	UsedCount     int       `json:"used_count"`
	RestaurantID  string    `json:"restaurant_id,omitempty"` // empty = platform-wide
	IsActive      bool      `json:"is_active"`
	ApplicableTo  string    `json:"applicable_to"` // all | new_users | gold_members
	CreatedAt     time.Time `json:"created_at"`
}

// ValidateCouponRequest for POST /cart/validate-coupon
type ValidateCouponRequest struct {
	Code       string  `json:"code" binding:"required"`
	OrderTotal float64 `json:"order_total" binding:"required,gt=0"`
}

// IsValid checks if the coupon can be used
func (c *Coupon) IsValid(orderTotal float64) (bool, string) {
	if !c.IsActive {
		return false, "Coupon is not active"
	}
	now := time.Now()
	if now.Before(c.ValidFrom) {
		return false, "Coupon is not yet valid"
	}
	if now.After(c.ValidUntil) {
		return false, "Coupon has expired"
	}
	if c.UsedCount >= c.UsageLimit {
		return false, "Coupon usage limit reached"
	}
	if orderTotal < c.MinOrderValue {
		return false, "Minimum order value not met"
	}
	return true, ""
}

// CalculateDiscount computes the discount amount
func (c *Coupon) CalculateDiscount(orderTotal float64) float64 {
	var discount float64
	if c.DiscountType == "percentage" {
		discount = orderTotal * c.DiscountValue / 100
	} else {
		discount = c.DiscountValue
	}
	if c.MaxDiscount > 0 && discount > c.MaxDiscount {
		discount = c.MaxDiscount
	}
	return discount
}
