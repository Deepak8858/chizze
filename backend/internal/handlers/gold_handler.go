package handlers

import (
	"time"

	"github.com/chizze/backend/internal/models"
	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/pkg/utils"
	"github.com/gin-gonic/gin"
)

// GoldHandler handles Chizze Gold membership endpoints
type GoldHandler struct {
	appwrite *services.AppwriteService
}

// NewGoldHandler creates a gold handler
func NewGoldHandler(aw *services.AppwriteService) *GoldHandler {
	return &GoldHandler{appwrite: aw}
}

// GetPlans returns available Gold membership plans
// @Summary      Get Gold membership plans
// @Description  Returns all available Chizze Gold membership plans
// @Tags         Gold
// @Accept       json
// @Produce      json
// @Success      200  {array}   models.GoldPlan
// @Security     BearerAuth
// @Router       /api/v1/gold/plans [get]
func (h *GoldHandler) GetPlans(c *gin.Context) {
	plans := models.GoldPlans()
	utils.Success(c, plans)
}

// GetStatus returns the user's current Gold membership status
// @Summary      Get Gold membership status
// @Description  Returns the authenticated user's current Gold membership status and subscription details
// @Tags         Gold
// @Accept       json
// @Produce      json
// @Success      200  {object}  map[string]interface{}
// @Security     BearerAuth
// @Router       /api/v1/gold/status [get]
func (h *GoldHandler) GetStatus(c *gin.Context) {
	userID := c.GetString("user_id")

	result, err := h.appwrite.GetActiveGoldSubscription(userID)
	if err != nil || result.Total == 0 {
		utils.Success(c, gin.H{
			"is_gold_member": false,
			"subscription":   nil,
		})
		return
	}

	utils.Success(c, gin.H{
		"is_gold_member": true,
		"subscription":   result.Documents[0],
	})
}

// Subscribe creates a new Gold membership subscription
// @Summary      Subscribe to Gold membership
// @Description  Creates a new Chizze Gold membership subscription for the authenticated user
// @Tags         Gold
// @Accept       json
// @Produce      json
// @Param        body  body      models.SubscribeGoldRequest  true  "Subscription plan and payment details"
// @Success      201  {object}  map[string]interface{}
// @Failure      400  {object}  map[string]interface{}
// @Failure      500  {object}  map[string]interface{}
// @Security     BearerAuth
// @Router       /api/v1/gold/subscribe [post]
func (h *GoldHandler) Subscribe(c *gin.Context) {
	userID := c.GetString("user_id")

	var req models.SubscribeGoldRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Plan ID and payment ID are required")
		return
	}

	// Verify plan exists
	plans := models.GoldPlans()
	var selectedPlan *models.GoldPlan
	for _, p := range plans {
		if p.Type == req.PlanType {
			selectedPlan = &p
			break
		}
	}
	if selectedPlan == nil {
		utils.BadRequest(c, "Invalid plan")
		return
	}

	// Check for existing active subscription
	existing, err := h.appwrite.GetActiveGoldSubscription(userID)
	if err == nil && existing.Total > 0 {
		utils.BadRequest(c, "Already an active Gold member")
		return
	}

	// Map plan type to duration days
	durationDays := map[string]int{"monthly": 30, "quarterly": 90, "annual": 365}[selectedPlan.Type]
	if durationDays == 0 {
		durationDays = 30
	}

	now := time.Now()
	data := map[string]interface{}{
		"user_id":        userID,
		"plan_type":      req.PlanType,
		"plan_name":      selectedPlan.Label,
		"amount":         selectedPlan.Price,
		"duration_days":  durationDays,
		"payment_id":     req.PaymentID,
		"status":         "active",
		"started_at":     now.Format(time.RFC3339),
		"expires_at":     now.AddDate(0, 0, durationDays).Format(time.RFC3339),
		"auto_renew":     true,
		"created_at":     now.Format(time.RFC3339),
	}

	doc, err := h.appwrite.CreateGoldSubscription("unique()", data)
	if err != nil {
		utils.InternalError(c, "Failed to create subscription")
		return
	}

	// Update user's gold status
	_, _ = h.appwrite.UpdateUser(userID, map[string]interface{}{
		"is_gold_member": true,
	})

	utils.Created(c, doc)
}

// Cancel cancels the user's Gold membership
// @Summary      Cancel Gold membership
// @Description  Cancels the authenticated user's active Gold membership subscription
// @Tags         Gold
// @Accept       json
// @Produce      json
// @Success      200  {object}  map[string]interface{}
// @Failure      404  {object}  map[string]interface{}
// @Failure      500  {object}  map[string]interface{}
// @Security     BearerAuth
// @Router       /api/v1/gold/cancel [put]
func (h *GoldHandler) Cancel(c *gin.Context) {
	userID := c.GetString("user_id")

	result, err := h.appwrite.GetActiveGoldSubscription(userID)
	if err != nil || result.Total == 0 {
		utils.NotFound(c, "No active Gold subscription found")
		return
	}

	docID, _ := result.Documents[0]["$id"].(string)
	_, err = h.appwrite.UpdateGoldSubscription(docID, map[string]interface{}{
		"status":     "cancelled",
		"auto_renew": false,
	})
	if err != nil {
		utils.InternalError(c, "Failed to cancel subscription")
		return
	}

	// Update user gold status
	_, _ = h.appwrite.UpdateUser(userID, map[string]interface{}{
		"is_gold_member": false,
	})

	utils.Success(c, gin.H{"message": "Gold membership cancelled"})
}
