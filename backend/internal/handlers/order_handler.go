package handlers

import (
	"time"

	"github.com/chizze/backend/internal/middleware"
	"github.com/chizze/backend/internal/models"
	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/pkg/appwrite"
	"github.com/chizze/backend/pkg/utils"
	"github.com/gin-gonic/gin"
)

// OrderHandler handles order endpoints
type OrderHandler struct {
	appwrite *services.AppwriteService
	orders   *services.OrderService
}

// NewOrderHandler creates an order handler
func NewOrderHandler(aw *services.AppwriteService, os *services.OrderService) *OrderHandler {
	return &OrderHandler{appwrite: aw, orders: os}
}

// PlaceOrder creates a new order
// POST /api/v1/orders
func (h *OrderHandler) PlaceOrder(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req models.PlaceOrderRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Invalid order data")
		return
	}

	// Calculate fees
	itemTotal := 0.0
	for _, item := range req.Items {
		itemTotal += item.Price * float64(item.Quantity)
	}
	deliveryFee, platformFee, gst := h.orders.CalculateFees(itemTotal, 5.0) // 5km default
	grandTotal := itemTotal + deliveryFee + platformFee + gst - 0 + req.Tip // discount = 0 for now

	orderNumber := h.orders.GenerateOrderNumber()

	orderData := map[string]interface{}{
		"order_number":           orderNumber,
		"customer_id":            userID,
		"restaurant_id":          req.RestaurantID,
		"delivery_address_id":    req.DeliveryAddressID,
		"items":                  req.Items,
		"item_total":             itemTotal,
		"delivery_fee":           deliveryFee,
		"platform_fee":           platformFee,
		"gst":                    gst,
		"discount":               0,
		"coupon_code":            req.CouponCode,
		"tip":                    req.Tip,
		"grand_total":            grandTotal,
		"payment_method":         req.PaymentMethod,
		"payment_status":         models.PaymentPending,
		"status":                 models.OrderStatusPlaced,
		"special_instructions":   req.SpecialInstructions,
		"delivery_instructions":  req.DeliveryInstructions,
		"estimated_delivery_min": 30,
		"placed_at":              time.Now().Format(time.RFC3339),
	}

	doc, err := h.appwrite.CreateOrder("unique()", orderData)
	if err != nil {
		utils.InternalError(c, "Failed to create order")
		return
	}

	utils.Created(c, doc)
}

// GetOrder returns order details
// GET /api/v1/orders/:id
func (h *OrderHandler) GetOrder(c *gin.Context) {
	orderID := c.Param("id")
	order, err := h.appwrite.GetOrder(orderID)
	if err != nil {
		utils.NotFound(c, "Order not found")
		return
	}
	utils.Success(c, order)
}

// ListOrders returns order history for current user
// GET /api/v1/orders
func (h *OrderHandler) ListOrders(c *gin.Context) {
	userID := middleware.GetUserID(c)
	result, err := h.appwrite.ListOrders([]string{
		appwrite.QueryEqual("customer_id", userID),
		appwrite.QueryOrderDesc("placed_at"),
	})
	if err != nil {
		utils.InternalError(c, "Failed to fetch orders")
		return
	}
	utils.Success(c, result.Documents)
}

// CancelOrder cancels an order
// PUT /api/v1/orders/:id/cancel
func (h *OrderHandler) CancelOrder(c *gin.Context) {
	orderID := c.Param("id")

	var req models.CancelOrderRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Cancellation reason is required")
		return
	}

	order, err := h.appwrite.GetOrder(orderID)
	if err != nil {
		utils.NotFound(c, "Order not found")
		return
	}

	currentStatus, _ := order["status"].(string)
	if err := h.orders.ValidateTransition(currentStatus, models.OrderStatusCancelled); err != nil {
		utils.BadRequest(c, err.Error())
		return
	}

	now := time.Now().Format(time.RFC3339)
	updated, err := h.appwrite.UpdateOrder(orderID, map[string]interface{}{
		"status":              models.OrderStatusCancelled,
		"cancelled_at":        now,
		"cancellation_reason": req.Reason,
		"cancelled_by":        "customer",
	})
	if err != nil {
		utils.InternalError(c, "Failed to cancel order")
		return
	}
	utils.Success(c, updated)
}

// UpdateStatus updates order status (for partner/delivery)
// PUT /api/v1/orders/:id/status
func (h *OrderHandler) UpdateStatus(c *gin.Context) {
	orderID := c.Param("id")

	var req struct {
		Status string `json:"status" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Status is required")
		return
	}

	order, err := h.appwrite.GetOrder(orderID)
	if err != nil {
		utils.NotFound(c, "Order not found")
		return
	}

	currentStatus, _ := order["status"].(string)
	if err := h.orders.ValidateTransition(currentStatus, req.Status); err != nil {
		utils.BadRequest(c, err.Error())
		return
	}

	updateData := map[string]interface{}{
		"status": req.Status,
	}

	// Set timestamp for the new status
	now := time.Now().Format(time.RFC3339)
	switch req.Status {
	case models.OrderStatusConfirmed:
		updateData["confirmed_at"] = now
	case models.OrderStatusReady:
		updateData["prepared_at"] = now
	case models.OrderStatusPickedUp:
		updateData["picked_up_at"] = now
	case models.OrderStatusDelivered:
		updateData["delivered_at"] = now
	}

	updated, err := h.appwrite.UpdateOrder(orderID, updateData)
	if err != nil {
		utils.InternalError(c, "Failed to update order status")
		return
	}
	utils.Success(c, updated)
}
