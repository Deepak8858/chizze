package handlers

import (
	"github.com/chizze/backend/internal/middleware"
	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/pkg/utils"
	"github.com/gin-gonic/gin"
)

// DeliveryHandler handles delivery partner endpoints
type DeliveryHandler struct {
	appwrite *services.AppwriteService
	geo      *services.GeoService
}

// NewDeliveryHandler creates a delivery handler
func NewDeliveryHandler(aw *services.AppwriteService, geo *services.GeoService) *DeliveryHandler {
	return &DeliveryHandler{appwrite: aw, geo: geo}
}

// ToggleOnline sets delivery partner online/offline
// PUT /api/v1/delivery/status
func (h *DeliveryHandler) ToggleOnline(c *gin.Context) {
	userID := middleware.GetUserID(c)
	var req struct {
		IsOnline bool `json:"is_online"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Invalid request")
		return
	}

	partnerResult, err := h.appwrite.GetDeliveryPartner(userID)
	if err != nil || partnerResult.Total == 0 {
		utils.NotFound(c, "Delivery partner profile not found")
		return
	}

	partnerID, _ := partnerResult.Documents[0]["$id"].(string)
	updated, err := h.appwrite.UpdateDeliveryPartner(partnerID, map[string]interface{}{
		"is_online": req.IsOnline,
	})
	if err != nil {
		utils.InternalError(c, "Failed to update status")
		return
	}
	utils.Success(c, updated)
}

// UpdateLocation pushes delivery partner location
// PUT /api/v1/delivery/location
func (h *DeliveryHandler) UpdateLocation(c *gin.Context) {
	userID := middleware.GetUserID(c)
	var req struct {
		Latitude  float64 `json:"latitude" binding:"required"`
		Longitude float64 `json:"longitude" binding:"required"`
		Heading   float64 `json:"heading"`
		Speed     float64 `json:"speed"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Latitude and longitude are required")
		return
	}

	partnerResult, err := h.appwrite.GetDeliveryPartner(userID)
	if err != nil || partnerResult.Total == 0 {
		utils.NotFound(c, "Delivery partner not found")
		return
	}

	partnerID, _ := partnerResult.Documents[0]["$id"].(string)
	_, err = h.appwrite.UpdateDeliveryPartner(partnerID, map[string]interface{}{
		"current_latitude":  req.Latitude,
		"current_longitude": req.Longitude,
	})
	if err != nil {
		utils.InternalError(c, "Failed to update location")
		return
	}
	utils.Success(c, gin.H{"message": "Location updated"})
}

// AcceptOrder accepts a delivery request
// PUT /api/v1/delivery/orders/:id/accept
func (h *DeliveryHandler) AcceptOrder(c *gin.Context) {
	orderID := c.Param("id")
	userID := middleware.GetUserID(c)

	_, err := h.appwrite.UpdateOrder(orderID, map[string]interface{}{
		"delivery_partner_id": userID,
		"status":              "picked_up",
	})
	if err != nil {
		utils.InternalError(c, "Failed to accept order")
		return
	}
	utils.Success(c, gin.H{"message": "Order accepted", "order_id": orderID})
}
