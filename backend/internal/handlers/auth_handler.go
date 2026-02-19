package handlers

import (
	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/pkg/utils"
	"github.com/gin-gonic/gin"
)

// AuthHandler handles authentication endpoints
type AuthHandler struct {
	appwrite *services.AppwriteService
}

// NewAuthHandler creates an auth handler
func NewAuthHandler(aw *services.AppwriteService) *AuthHandler {
	return &AuthHandler{appwrite: aw}
}

// SendOTP sends OTP to phone number
// POST /api/v1/auth/send-otp
func (h *AuthHandler) SendOTP(c *gin.Context) {
	var req struct {
		Phone string `json:"phone" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Phone number is required")
		return
	}

	if !utils.ValidatePhone(req.Phone) {
		utils.BadRequest(c, "Invalid phone number format. Use +91XXXXXXXXXX")
		return
	}

	// TODO: Integrate with Appwrite phone auth or SMS provider
	utils.Success(c, gin.H{
		"message": "OTP sent successfully",
		"phone":   req.Phone,
	})
}

// VerifyOTP verifies OTP and returns session
// POST /api/v1/auth/verify-otp
func (h *AuthHandler) VerifyOTP(c *gin.Context) {
	var req struct {
		Phone string `json:"phone" binding:"required"`
		OTP   string `json:"otp" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Phone and OTP are required")
		return
	}

	// TODO: Verify OTP via Appwrite, create/get session, return JWT
	utils.Success(c, gin.H{
		"message": "OTP verified",
		"token":   "jwt_token_placeholder",
		"user":    gin.H{"phone": req.Phone, "role": "customer"},
	})
}

// Refresh refreshes the JWT token
// POST /api/v1/auth/refresh
func (h *AuthHandler) Refresh(c *gin.Context) {
	// TODO: Validate refresh token, issue new JWT
	utils.Success(c, gin.H{"token": "new_jwt_token_placeholder"})
}

// Logout invalidates the session
// DELETE /api/v1/auth/logout
func (h *AuthHandler) Logout(c *gin.Context) {
	// TODO: Invalidate Appwrite session
	utils.Success(c, gin.H{"message": "Logged out successfully"})
}
