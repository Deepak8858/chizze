package handlers

import (
	"time"

	"github.com/chizze/backend/internal/models"
	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/pkg/appwrite"
	"github.com/chizze/backend/pkg/utils"
	"github.com/gin-gonic/gin"
)

// CouponHandler handles coupon endpoints
type CouponHandler struct {
	appwrite *services.AppwriteService
}

// NewCouponHandler creates a coupon handler
func NewCouponHandler(aw *services.AppwriteService) *CouponHandler {
	return &CouponHandler{appwrite: aw}
}

// parseCouponDoc safely parses an Appwrite document into a Coupon struct
func parseCouponDoc(doc map[string]interface{}) *models.Coupon {
	c := &models.Coupon{}
	c.Code, _ = doc["code"].(string)
	c.Description, _ = doc["description"].(string)
	c.DiscountType, _ = doc["discount_type"].(string)
	c.DiscountValue, _ = doc["discount_value"].(float64)
	c.MaxDiscount, _ = doc["max_discount"].(float64)
	c.MinOrderValue, _ = doc["min_order_value"].(float64)
	c.IsActive, _ = doc["is_active"].(bool)
	c.RestaurantID, _ = doc["restaurant_id"].(string)
	c.ApplicableTo, _ = doc["applicable_to"].(string)

	// Parse int fields safely via float64
	if v, ok := doc["usage_limit"].(float64); ok {
		c.UsageLimit = int(v)
	}
	if v, ok := doc["used_count"].(float64); ok {
		c.UsedCount = int(v)
	}

	// Parse date strings from Appwrite (they come as RFC3339 strings, not time.Time)
	if s, ok := doc["valid_from"].(string); ok && s != "" {
		c.ValidFrom, _ = time.Parse(time.RFC3339, s)
	}
	if s, ok := doc["valid_until"].(string); ok && s != "" {
		c.ValidUntil, _ = time.Parse(time.RFC3339, s)
	}

	return c
}

// ListAvailable returns active coupons
// GET /api/v1/coupons
func (h *CouponHandler) ListAvailable(c *gin.Context) {
	result, err := h.appwrite.ListCoupons([]string{
		appwrite.QueryEqual("is_active", true),
	})
	if err != nil {
		utils.InternalError(c, "Failed to fetch coupons")
		return
	}
	utils.Success(c, result.Documents)
}

// Validate checks if a coupon is valid for a given order total
// POST /api/v1/cart/validate-coupon
func (h *CouponHandler) Validate(c *gin.Context) {
	var req models.ValidateCouponRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Code and order total are required")
		return
	}

	// Find coupon by code
	result, err := h.appwrite.ListCoupons([]string{
		appwrite.QueryEqual("code", req.Code),
	})
	if err != nil || result.Total == 0 {
		utils.NotFound(c, "Coupon not found")
		return
	}

	coupon := parseCouponDoc(result.Documents[0])

	valid, reason := coupon.IsValid(req.OrderTotal)
	if !valid {
		utils.BadRequest(c, reason)
		return
	}

	discount := coupon.CalculateDiscount(req.OrderTotal)
	utils.Success(c, gin.H{
		"valid":    true,
		"code":     req.Code,
		"discount": discount,
		"message":  coupon.Description,
	})
}
