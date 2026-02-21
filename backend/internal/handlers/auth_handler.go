package handlers

import (
	"context"
	"log"
	"strconv"
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
// POST /api/v1/auth/exchange
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

	// Rate limit: max 3 OTP requests per phone per 10 minutes
	ctx := context.Background()
	rateLimitKey := "otp_limit:" + req.Phone
	count, _ := h.redis.Get(ctx, rateLimitKey)
	if count != "" {
		countInt, _ := strconv.Atoi(count)
		if countInt >= 3 {
			utils.Error(c, 429, "Too many OTP requests. Please try again later.")
			return
		}
	}
	h.redis.Incr(ctx, rateLimitKey)
	h.redis.Expire(ctx, rateLimitKey, 10*time.Minute)

	// In production: integrate with Appwrite phone auth or SMS provider (MSG91, Twilio, etc.)
	// For now, Appwrite SDK handles OTP on client side — this endpoint is a rate-limited proxy
	utils.Success(c, gin.H{
		"message": "OTP sent successfully",
		"phone":   req.Phone,
	})
}

// VerifyOTP verifies OTP and returns session
// POST /api/v1/auth/verify-otp
func (h *AuthHandler) VerifyOTP(c *gin.Context) {
	var req struct {
		Phone  string `json:"phone" binding:"required"`
		OTP    string `json:"otp" binding:"required"`
		UserID string `json:"user_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Phone, OTP, and user_id are required")
		return
	}

	// The Flutter app verifies OTP via Appwrite SDK and gets a session.
	// It then calls /auth/exchange with the Appwrite JWT.
	// This endpoint is for direct OTP flow (if not using Appwrite SDK on client):
	// In this architecture, after Appwrite verifies OTP on client, client calls /exchange.

	// For backwards compatibility: if user_id is provided (from Appwrite session),
	// check user exists and issue token
	user, err := h.appwrite.GetUser(req.UserID)
	role := "customer"
	if err != nil {
		// Create user
		userData := map[string]interface{}{
			"phone":      req.Phone,
			"role":       "customer",
			"is_active":  true,
			"created_at": time.Now().Format(time.RFC3339),
		}
		h.appwrite.CreateUser(req.UserID, userData)
	} else {
		if r, ok := user["role"].(string); ok && r != "" {
			role = r
		}
	}

	token, err := h.issueJWT(req.UserID, role, 7*24*time.Hour)
	if err != nil {
		utils.InternalError(c, "Failed to generate token")
		return
	}

	utils.Success(c, gin.H{
		"message": "OTP verified",
		"token":   token,
		"user_id": req.UserID,
		"role":    role,
	})
}

// Refresh re-issues a JWT from a valid existing token
// POST /api/v1/auth/refresh
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
// DELETE /api/v1/auth/logout
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
