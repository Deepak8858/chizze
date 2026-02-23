package handlers

import (
	"fmt"
	"log"
	"math/rand"
	"time"

	"github.com/chizze/backend/internal/middleware"
	"github.com/chizze/backend/internal/models"
	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/pkg/utils"
	"github.com/gin-gonic/gin"
)

// ReferralHandler handles referral system endpoints
type ReferralHandler struct {
	appwrite *services.AppwriteService
}

// NewReferralHandler creates a referral handler
func NewReferralHandler(aw *services.AppwriteService) *ReferralHandler {
	return &ReferralHandler{appwrite: aw}
}

// GetCode returns the user's referral code, generating one if needed
// @Summary      Get referral code
// @Description  Returns the authenticated user's referral code and share link, generating a new code if none exists
// @Tags         Referrals
// @Accept       json
// @Produce      json
// @Success      200  {object}  map[string]interface{}
// @Failure      500  {object}  map[string]interface{}
// @Security     BearerAuth
// @Router       /api/v1/referrals/code [get]
func (h *ReferralHandler) GetCode(c *gin.Context) {
	userID := middleware.GetUserID(c)

	user, err := h.appwrite.GetUser(userID)
	if err != nil {
		utils.InternalError(c, "Failed to fetch user")
		return
	}

	code, _ := user["referral_code"].(string)
	if code == "" {
		// Generate a unique referral code
		code = generateReferralCode()
		_, err = h.appwrite.UpdateUser(userID, map[string]interface{}{
			"referral_code": code,
		})
		if err != nil {
			utils.InternalError(c, "Failed to generate referral code")
			return
		}
	}

	utils.Success(c, gin.H{
		"referral_code": code,
		"share_link":    fmt.Sprintf("https://chizze.app/refer/%s", code),
	})
}

// Apply applies a referral code for the current user
// @Summary      Apply a referral code
// @Description  Applies a referral code for the authenticated user, granting rewards to both referrer and referee
// @Tags         Referrals
// @Accept       json
// @Produce      json
// @Param        body  body      models.ApplyReferralRequest  true  "Referral code to apply"
// @Success      200  {object}  map[string]interface{}
// @Failure      400  {object}  map[string]interface{}
// @Failure      404  {object}  map[string]interface{}
// @Failure      500  {object}  map[string]interface{}
// @Security     BearerAuth
// @Router       /api/v1/referrals/apply [post]
func (h *ReferralHandler) Apply(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req models.ApplyReferralRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Referral code is required")
		return
	}

	// Check if user already used a referral
	user, err := h.appwrite.GetUser(userID)
	if err != nil {
		utils.InternalError(c, "Failed to fetch user")
		return
	}
	referredBy, _ := user["referred_by"].(string)
	if referredBy != "" {
		utils.BadRequest(c, "You have already used a referral code")
		return
	}

	// Find the referrer by code
	result, err := h.appwrite.FindReferralByCode(req.ReferralCode)
	if err != nil || result.Total == 0 {
		utils.NotFound(c, "Invalid referral code")
		return
	}

	referrerID, _ := result.Documents[0]["$id"].(string)

	// Can't refer yourself
	if referrerID == userID {
		utils.BadRequest(c, "Cannot use your own referral code")
		return
	}

	// Create referral record
	data := map[string]interface{}{
		"referrer_user_id": referrerID,
		"referred_user_id": userID,
		"referral_code":    req.ReferralCode,
		"status":           "completed",
		"reward_amount":    100.0, // ₹100 reward for both
		"created_at":       time.Now().Format(time.RFC3339),
	}

	_, err = h.appwrite.CreateReferral("unique()", data)
	if err != nil {
		utils.InternalError(c, "Failed to apply referral")
		return
	}

	// Update referred user
	if _, err := h.appwrite.UpdateUser(userID, map[string]interface{}{
		"referred_by": req.ReferralCode,
	}); err != nil {
		log.Printf("[referral] failed to update referred_by for %s: %v", userID, err)
	}

	utils.Success(c, gin.H{
		"message": "Referral applied! You and your friend both get ₹100 off your next order",
		"reward":  100.0,
	})
}

// ListReferrals returns the user's referral history
// @Summary      List referrals
// @Description  Returns the authenticated user's referral history and total earnings
// @Tags         Referrals
// @Accept       json
// @Produce      json
// @Success      200  {object}  map[string]interface{}
// @Failure      500  {object}  map[string]interface{}
// @Security     BearerAuth
// @Router       /api/v1/referrals [get]
func (h *ReferralHandler) ListReferrals(c *gin.Context) {
	userID := middleware.GetUserID(c)

	result, err := h.appwrite.ListReferrals(userID)
	if err != nil {
		utils.InternalError(c, "Failed to fetch referrals")
		return
	}

	utils.Success(c, gin.H{
		"referrals":    result.Documents,
		"total":        result.Total,
		"total_earned": float64(result.Total) * 100.0,
	})
}

// generateReferralCode creates a random 8-character alphanumeric code
func generateReferralCode() string {
	const charset = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	code := make([]byte, 8)
	for i := range code {
		code[i] = charset[rand.Intn(len(charset))]
	}
	return "CHZ" + string(code)
}
