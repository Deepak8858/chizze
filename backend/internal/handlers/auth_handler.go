package handlers

import (
	"context"
	"log"
	"time"

	"github.com/chizze/backend/internal/config"
	"github.com/chizze/backend/internal/middleware"
	"github.com/chizze/backend/internal/services"
	redispkg "github.com/chizze/backend/pkg/redis"
	"github.com/chizze/backend/pkg/utils"
	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

// AuthHandler handles authentication endpoints
type AuthHandler struct {
	appwrite *services.AppwriteService
	redis    *redispkg.Client
	cfg      *config.Config
}

// NewAuthHandler creates an auth handler
func NewAuthHandler(aw *services.AppwriteService, redis *redispkg.Client, cfg *config.Config) *AuthHandler {
	return &AuthHandler{appwrite: aw, redis: redis, cfg: cfg}
}

// issueJWT creates a signed JWT for internal use
func (h *AuthHandler) issueJWT(userID, role string, duration time.Duration) (string, error) {
	claims := middleware.AuthClaims{
		UserID: userID,
		Role:   role,
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    "chizze-api",
			Subject:   userID,
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(duration)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(h.cfg.JWTSecret))
}

// Exchange validates an Appwrite client JWT and issues a Chizze API JWT
// @Summary Exchange Appwrite JWT for Chizze API token
// @Description Validates an Appwrite client JWT and issues a Chizze API JWT. Creates user document if not exists.
// @Tags Auth
// @Accept json
// @Produce json
// @Param request body object true "JSON with jwt (string, required) and role (string, optional)"
// @Success 200 {object} map[string]interface{} "token, user_id, role, is_new"
// @Failure 400 {object} map[string]interface{}
// @Failure 401 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/v1/auth/exchange [post]
func (h *AuthHandler) Exchange(c *gin.Context) {
	var req struct {
		AppwriteJWT string `json:"jwt" binding:"required"`
		Role        string `json:"role"` // optional: role selected by user on signup
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Appwrite JWT is required")
		return
	}

	// Validate the Appwrite JWT by calling Appwrite GET /account
	account, err := h.appwrite.Client().VerifyJWT(req.AppwriteJWT)
	if err != nil {
		log.Printf("Appwrite JWT verification failed: %v", err)
		utils.Unauthorized(c, "Invalid or expired Appwrite session")
		return
	}

	appwriteUserID, _ := account["$id"].(string)
	if appwriteUserID == "" {
		utils.Unauthorized(c, "Could not extract user ID from Appwrite account")
		return
	}

	// Check if user exists in our users collection
	user, err := h.appwrite.GetUser(appwriteUserID)
	role := "customer" // default role
	isNew := false

	if err != nil {
		// User doesn't exist — create a new user doc
		isNew = true
		phone, _ := account["phone"].(string)
		email, _ := account["email"].(string)
		name, _ := account["name"].(string)

		// Use the role selected by user, or default to customer
		if req.Role != "" {
			role = req.Role
		}

		userData := map[string]interface{}{
			"phone":      phone,
			"email":      email,
			"name":       name,
			"role":       role,
			"is_active":  true,
			"created_at": time.Now().Format(time.RFC3339),
		}
		_, createErr := h.appwrite.CreateUser(appwriteUserID, userData)
		if createErr != nil {
			log.Printf("Failed to create user doc: %v", createErr)
			// Don't fail — user might already exist via race condition
		}
	} else {
		// Existing user — read role
		if r, ok := user["role"].(string); ok && r != "" {
			role = r
		}
	}

	// Issue our JWT (valid for 7 days)
	token, err := h.issueJWT(appwriteUserID, role, 7*24*time.Hour)
	if err != nil {
		utils.InternalError(c, "Failed to generate token")
		return
	}

	utils.Success(c, gin.H{
		"token":   token,
		"user_id": appwriteUserID,
		"role":    role,
		"is_new":  isNew,
	})
}

// SendOTP sends OTP to phone number
// @Summary Send OTP to phone number
// @Description Sends an OTP to the given phone number with rate limiting (max 3 per 10 minutes)
// @Tags Auth
// @Accept json
// @Produce json
// @Param request body object true "JSON with phone (string, required, format: +91XXXXXXXXXX)"
// @Success 200 {object} map[string]interface{} "message, phone"
// @Failure 400 {object} map[string]interface{}
// @Failure 429 {object} map[string]interface{}
// @Router /api/v1/auth/send-otp [post]
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

	// Rate limit: max 3 OTP requests per phone per 10 minutes (atomic)
	ctx := context.Background()
	rateLimitKey := "otp_limit:" + req.Phone
	allowed, _, _ := h.redis.RateLimitCheck(ctx, rateLimitKey, 3, 10*time.Minute)
	if !allowed {
		utils.Error(c, 429, "Too many OTP requests. Please try again later.")
		return
	}

	// In production: integrate with Appwrite phone auth or SMS provider (MSG91, Twilio, etc.)
	// For now, Appwrite SDK handles OTP on client side — this endpoint is a rate-limited proxy
	utils.Success(c, gin.H{
		"message": "OTP sent successfully",
		"phone":   req.Phone,
	})
}

// VerifyOTP verifies OTP and returns session
// @Summary Verify OTP and issue token
// @Description Verifies OTP for a phone number and returns a JWT token
// @Tags Auth
// @Accept json
// @Produce json
// @Param request body object true "JSON with phone (string), otp (string), user_id (string) — all required"
// @Success 200 {object} map[string]interface{} "message, token, user_id, role"
// @Failure 400 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/v1/auth/verify-otp [post]
func (h *AuthHandler) VerifyOTP(c *gin.Context) {
	var req struct {
		Phone       string `json:"phone" binding:"required"`
		OTP         string `json:"otp" binding:"required"`
		UserID      string `json:"user_id"`
		AppwriteJWT string `json:"appwrite_jwt" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Phone, OTP, and appwrite_jwt are required")
		return
	}

	// Validate the Appwrite JWT to prove OTP was actually verified on client
	account, err := h.appwrite.Client().VerifyJWT(req.AppwriteJWT)
	if err != nil {
		log.Printf("OTP verify: Appwrite JWT validation failed: %v", err)
		utils.Unauthorized(c, "Invalid or expired session. Please verify OTP again.")
		return
	}

	appwriteUserID, _ := account["$id"].(string)
	if appwriteUserID == "" {
		utils.Unauthorized(c, "Could not extract user ID from Appwrite account")
		return
	}

	// Verify phone matches the account
	accountPhone, _ := account["phone"].(string)
	if accountPhone != "" && accountPhone != req.Phone {
		utils.BadRequest(c, "Phone number does not match the verified session")
		return
	}

	// Check if user exists or create
	user, err := h.appwrite.GetUser(appwriteUserID)
	role := "customer"
	if err != nil {
		// Create user
		userData := map[string]interface{}{
			"phone":      req.Phone,
			"role":       "customer",
			"is_active":  true,
			"created_at": time.Now().Format(time.RFC3339),
		}
		h.appwrite.CreateUser(appwriteUserID, userData)
	} else {
		if r, ok := user["role"].(string); ok && r != "" {
			role = r
		}
	}

	token, err := h.issueJWT(appwriteUserID, role, 7*24*time.Hour)
	if err != nil {
		utils.InternalError(c, "Failed to generate token")
		return
	}

	utils.Success(c, gin.H{
		"message": "OTP verified",
		"token":   token,
		"user_id": appwriteUserID,
		"role":    role,
	})
}

// Refresh re-issues a JWT from a valid existing token
// @Summary Refresh JWT token
// @Description Re-issues a new JWT from a valid existing token. Token must not be blacklisted.
// @Tags Auth
// @Produce json
// @Security BearerAuth
// @Success 200 {object} map[string]interface{} "token, user_id, role"
// @Failure 401 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/v1/auth/refresh [post]
func (h *AuthHandler) Refresh(c *gin.Context) {
	// Extract and validate the current token
	userID := middleware.GetUserID(c)
	role := middleware.GetUserRole(c)

	if userID == "" {
		utils.Unauthorized(c, "Invalid session")
		return
	}

	// Check if token is blacklisted
	ctx := context.Background()
	blacklisted, _ := h.redis.Exists(ctx, "token_blacklist:"+userID)
	if blacklisted {
		utils.Unauthorized(c, "Token has been revoked")
		return
	}

	// Issue new token
	token, err := h.issueJWT(userID, role, 7*24*time.Hour)
	if err != nil {
		utils.InternalError(c, "Failed to refresh token")
		return
	}

	utils.Success(c, gin.H{
		"token":   token,
		"user_id": userID,
		"role":    role,
	})
}

// Logout invalidates the session via Redis blacklist
// @Summary Logout user
// @Description Invalidates the user's session by blacklisting their token in Redis for 7 days
// @Tags Auth
// @Produce json
// @Security BearerAuth
// @Success 200 {object} map[string]interface{} "message"
// @Router /api/v1/auth/logout [delete]
func (h *AuthHandler) Logout(c *gin.Context) {
	userID := middleware.GetUserID(c)
	if userID == "" {
		utils.Success(c, gin.H{"message": "Logged out"})
		return
	}

	// Blacklist the user's tokens for the remainder of the JWT TTL (7 days)
	ctx := context.Background()
	h.redis.Set(ctx, "token_blacklist:"+userID, "1", 7*24*time.Hour)

	utils.Success(c, gin.H{"message": "Logged out successfully"})
}
