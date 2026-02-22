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
// @Summary      List scheduled orders
// @Description  Returns the authenticated user's scheduled orders
// @Tags         Scheduled Orders
// @Accept       json
// @Produce      json
// @Success      200  {array}   map[string]interface{}
// @Failure      500  {object}  map[string]interface{}
// @Security     BearerAuth
// @Router       /api/v1/orders/scheduled [get]
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
// @Summary      Create a scheduled order
// @Description  Creates a new scheduled order for the authenticated user
// @Tags         Scheduled Orders
// @Accept       json
// @Produce      json
// @Param        body  body      models.CreateScheduledOrderRequest  true  "Scheduled order data"
// @Success      201  {object}  map[string]interface{}
// @Failure      400  {object}  map[string]interface{}
// @Failure      404  {object}  map[string]interface{}
// @Failure      500  {object}  map[string]interface{}
// @Security     BearerAuth
// @Router       /api/v1/orders/scheduled [post]
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
// @Summary      Cancel a scheduled order
// @Description  Cancels an existing scheduled order by ID
// @Tags         Scheduled Orders
// @Accept       json
// @Produce      json
// @Param        id  path      string  true  "Scheduled order ID"
// @Success      200  {object}  map[string]interface{}
// @Failure      500  {object}  map[string]interface{}
// @Security     BearerAuth
// @Router       /api/v1/orders/scheduled/{id}/cancel [put]
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
