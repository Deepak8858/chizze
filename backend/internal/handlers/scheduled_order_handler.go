package handlers

import (
	"time"

	"github.com/chizze/backend/internal/models"
	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/pkg/utils"
	"github.com/gin-gonic/gin"
)

// ScheduledOrderHandler handles scheduled order endpoints
type ScheduledOrderHandler struct {
	appwrite *services.AppwriteService
}

// NewScheduledOrderHandler creates a scheduled order handler
func NewScheduledOrderHandler(aw *services.AppwriteService) *ScheduledOrderHandler {
	return &ScheduledOrderHandler{appwrite: aw}
}

// List returns the user's scheduled orders
// GET /api/v1/orders/scheduled
func (h *ScheduledOrderHandler) List(c *gin.Context) {
	userID := c.GetString("user_id")

	result, err := h.appwrite.ListScheduledOrders(userID)
	if err != nil {
		utils.InternalError(c, "Failed to fetch scheduled orders")
		return
	}
	utils.Success(c, result.Documents)
}

// Create creates a new scheduled order
// POST /api/v1/orders/scheduled
func (h *ScheduledOrderHandler) Create(c *gin.Context) {
	userID := c.GetString("user_id")

	var req models.CreateScheduledOrderRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Restaurant ID, items, address and schedule time are required")
		return
	}

	// Verify restaurant exists
	_, err := h.appwrite.GetRestaurant(req.RestaurantID)
	if err != nil {
		utils.NotFound(c, "Restaurant not found")
		return
	}

	data := map[string]interface{}{
		"user_id":       userID,
		"restaurant_id": req.RestaurantID,
		"items":         req.Items,
		"address_id":    req.AddressID,
		"scheduled_for": req.ScheduledFor,
		"coupon_code":   req.CouponCode,
		"status":        "scheduled",
		"created_at":    time.Now().Format(time.RFC3339),
	}

	doc, err := h.appwrite.CreateScheduledOrder("unique()", data)
	if err != nil {
		utils.InternalError(c, "Failed to schedule order")
		return
	}

	utils.Created(c, doc)
}

// Cancel cancels a scheduled order
// PUT /api/v1/orders/scheduled/:id/cancel
func (h *ScheduledOrderHandler) Cancel(c *gin.Context) {
	orderID := c.Param("id")

	_, err := h.appwrite.UpdateScheduledOrder(orderID, map[string]interface{}{
		"status": "cancelled",
	})
	if err != nil {
		utils.InternalError(c, "Failed to cancel scheduled order")
		return
	}

	utils.Success(c, gin.H{"message": "Scheduled order cancelled"})
}
