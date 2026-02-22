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
// GET /api/v1/gold/plans
func (h *GoldHandler) GetPlans(c *gin.Context) {
	plans := models.GoldPlans()
	utils.Success(c, plans)
}

// GetStatus returns the user's current Gold membership status
// GET /api/v1/gold/status
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
// POST /api/v1/gold/subscribe
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
		if p.ID == req.PlanID {
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

	now := time.Now()
	data := map[string]interface{}{
		"user_id":        userID,
		"plan_id":        req.PlanID,
		"plan_name":      selectedPlan.Name,
		"amount":         selectedPlan.Price,
		"duration_days":  selectedPlan.DurationDays,
		"payment_id":     req.PaymentID,
		"status":         "active",
		"started_at":     now.Format(time.RFC3339),
		"expires_at":     now.AddDate(0, 0, selectedPlan.DurationDays).Format(time.RFC3339),
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
// PUT /api/v1/gold/cancel
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
