package handlers

import (
	"fmt"

	"github.com/chizze/backend/internal/models"
	"github.com/chizze/backend/internal/services"
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

// ListAvailable returns active coupons
// GET /api/v1/coupons
func (h *CouponHandler) ListAvailable(c *gin.Context) {
	result, err := h.appwrite.ListCoupons([]string{
		`equal("is_active", [true])`,
	})
	if err != nil {
		utils.InternalError(c, "Failed to fetch coupons")
		return
	}
	utils.Success(c, result.Documents)
}

// Validate checks if a coupon is valid for a given order
// POST /api/v1/cart/validate-coupon
func (h *CouponHandler) Validate(c *gin.Context) {
	var req models.ValidateCouponRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Code and order total are required")
		return
	}

	// Find coupon by code
	result, err := h.appwrite.ListCoupons([]string{
		fmt.Sprintf(`equal("code", ["%s"])`, req.Code),
	})
	if err != nil || result.Total == 0 {
		utils.NotFound(c, "Coupon not found")
		return
	}

	// Parse coupon from document
	doc := result.Documents[0]
	coupon := &models.Coupon{
		IsActive:      doc["is_active"].(bool),
		MinOrderValue: doc["min_order_value"].(float64),
		DiscountType:  doc["discount_type"].(string),
		DiscountValue: doc["discount_value"].(float64),
		MaxDiscount:   doc["max_discount"].(float64),
		UsageLimit:    int(doc["usage_limit"].(float64)),
		UsedCount:     int(doc["used_count"].(float64)),
	}

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
	})
}
