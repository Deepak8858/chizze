package handlers

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/chizze/backend/internal/config"
	"github.com/chizze/backend/internal/middleware"
	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/pkg/appwrite"
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
	phone, _ := account["phone"].(string)

	if err != nil {
		// No doc for this Appwrite user ID.
		// Appwrite may create a new user account (new ID) on each phone login,
		// so check if there's an existing doc for this phone number.
		var existingDoc map[string]interface{}
		if phone != "" {
			existingUsers, lookupErr := h.appwrite.ListUsers([]string{
				appwrite.QueryEqual("phone", phone),
				appwrite.QueryLimit(1),
			})
			if lookupErr == nil && existingUsers != nil && existingUsers.Total > 0 {
				existingDoc = existingUsers.Documents[0]
			}
		}

		if existingDoc != nil {
			// Found existing doc with same phone but different Appwrite user ID.
			// Migrate: delete old doc and create new one with current Appwrite user ID.
			oldID, _ := existingDoc["$id"].(string)
			if r, ok := existingDoc["role"].(string); ok && r != "" {
				role = r
			}
			// Use role from request if provided (user may be re-selecting role)
			if req.Role != "" {
				role = req.Role
			}

			// Copy fields from old doc
			migratedData := map[string]interface{}{
				"phone": phone,
				"role":  role,
			}
			for _, field := range []string{"name", "address", "avatar_url", "fcm_token", "referral_code", "referred_by", "default_address_id"} {
				if v, ok := existingDoc[field]; ok && v != nil {
					migratedData[field] = v
				}
			}
			for _, field := range []string{"latitude", "longitude"} {
				if v, ok := existingDoc[field]; ok && v != nil {
					migratedData[field] = v
				}
			}
			for _, field := range []string{"is_veg", "dark_mode", "is_gold_member"} {
				if v, ok := existingDoc[field]; ok {
					migratedData[field] = v
				}
			}
			if email, _ := existingDoc["email"].(string); email != "" {
				migratedData["email"] = email
			}

			// Delete old doc
			if deleteErr := h.appwrite.DeleteUser(oldID); deleteErr != nil {
				log.Printf("Failed to delete old user doc %s: %v", oldID, deleteErr)
			}
			// Create new doc with current Appwrite user ID
			if _, createErr := h.appwrite.CreateUser(appwriteUserID, migratedData); createErr != nil {
				log.Printf("Failed to create migrated user doc %s: %v", appwriteUserID, createErr)
			} else {
				log.Printf("Migrated user doc from %s to %s (phone=%s)", oldID, appwriteUserID, phone)
			}
			isNew = false
		} else {
			// Truly new user — no existing doc for this phone
			isNew = true
			email, _ := account["email"].(string)
			name, _ := account["name"].(string)

			if req.Role != "" {
				role = req.Role
			}

			userData := map[string]interface{}{
				"phone": phone,
				"name":  name,
				"role":  role,
			}
			if email != "" {
				userData["email"] = email
			}
			_, createErr := h.appwrite.CreateUser(appwriteUserID, userData)
			if createErr != nil {
				log.Printf("Failed to create user doc: %v", createErr)
			}
		}
	} else {
		// Existing user — read role
		if r, ok := user["role"].(string); ok && r != "" {
			role = r
		}
	}

	// For returning users, verify onboarding was actually completed.
	// If the role-specific record is missing, force onboarding.
	if !isNew {
		needsOnboarding := false
		switch role {
		case "restaurant_owner":
			existing, _ := h.appwrite.GetRestaurantByOwner(appwriteUserID)
			if existing == nil || existing.Total == 0 {
				needsOnboarding = true
			}
		case "delivery_partner":
			existing, _ := h.appwrite.GetDeliveryPartner(appwriteUserID)
			if existing == nil || existing.Total == 0 {
				needsOnboarding = true
			}
		}
		if needsOnboarding {
			isNew = true
			log.Printf("User %s (role=%s) missing role-specific record — marking as new for onboarding", appwriteUserID, role)
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
		// Create user with all required fields
		userData := map[string]interface{}{
			"name":  "",
			"phone": req.Phone,
			"role":  "customer",
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

// CheckPhone checks if a phone number is already registered
// @Summary Check if phone is registered
// @Description Checks whether a phone number exists in the users collection
// @Tags Auth
// @Accept json
// @Produce json
// @Param request body object true "JSON with phone (string, required)"
// @Success 200 {object} map[string]interface{} "exists (bool), user_name (string, if exists)"
// @Failure 400 {object} map[string]interface{}
// @Router /api/v1/auth/check-phone [post]
func (h *AuthHandler) CheckPhone(c *gin.Context) {
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

	// Search users collection for this phone number
	result, err := h.appwrite.ListUsers([]string{
		appwrite.QueryEqual("phone", req.Phone),
		appwrite.QueryLimit(1),
	})
	if err != nil {
		log.Printf("CheckPhone: failed to query users: %v", err)
		// Don't expose internal error — just say not found
		utils.Success(c, gin.H{"exists": false})
		return
	}

	if result != nil && result.Total > 0 {
		name, _ := result.Documents[0]["name"].(string)
		role, _ := result.Documents[0]["role"].(string)
		utils.Success(c, gin.H{
			"exists":    true,
			"user_name": name,
			"role":      role,
		})
		return
	}

	utils.Success(c, gin.H{"exists": false})
}

// Onboard completes user onboarding with role-specific data
// @Summary Complete user onboarding
// @Description Updates user profile and creates role-specific records (restaurant/delivery partner)
// @Tags Auth
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param request body object true "Onboarding data (role-specific fields)"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/v1/auth/onboard [post]
func (h *AuthHandler) Onboard(c *gin.Context) {
	userID := middleware.GetUserID(c)
	role := middleware.GetUserRole(c)

	if userID == "" {
		utils.Unauthorized(c, "Authentication required")
		return
	}

	var req map[string]interface{}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}

	// Extract common fields
	name, _ := req["name"].(string)
	email, _ := req["email"].(string)
	address, _ := req["address"].(string)
	latitude, _ := req["latitude"].(float64)
	longitude, _ := req["longitude"].(float64)

	if name == "" {
		utils.BadRequest(c, "Name is required")
		return
	}

	// Update user profile
	userUpdate := map[string]interface{}{
		"name": name,
	}
	if email != "" {
		userUpdate["email"] = email
	}
	if address != "" {
		userUpdate["address"] = address
	}
	if latitude != 0 {
		userUpdate["latitude"] = latitude
	}
	if longitude != 0 {
		userUpdate["longitude"] = longitude
	}

	_, err := h.appwrite.UpdateUser(userID, userUpdate)
	if err != nil {
		log.Printf("Onboard: UpdateUser failed for %s: %v — attempting create", userID, err)
		// User doc may not exist (e.g. if creation failed during login).
		// Build a complete user doc with all required fields and create it.
		createData := map[string]interface{}{
			"name":  name,
			"phone": "",
			"role":  role,
		}
		if email != "" {
			createData["email"] = email
		}
		if address != "" {
			createData["address"] = address
		}
		if latitude != 0 {
			createData["latitude"] = latitude
		}
		if longitude != 0 {
			createData["longitude"] = longitude
		}
		_, createErr := h.appwrite.CreateUser(userID, createData)
		if createErr != nil {
			log.Printf("Onboard: CreateUser also failed for %s: %v", userID, createErr)
			utils.InternalError(c, "Failed to update profile")
			return
		}
		log.Printf("Onboard: created user doc for %s (was missing)", userID)
	}

	// Handle role-specific setup
	switch role {
	case "restaurant_owner":
		restaurantName, _ := req["restaurant_name"].(string)
		restaurantAddress, _ := req["restaurant_address"].(string)
		cuisineType, _ := req["cuisine_type"].(string)
		city, _ := req["city"].(string)

		if restaurantName == "" {
			utils.BadRequest(c, "Restaurant name is required for restaurant partners")
			return
		}

		// city is required by Appwrite schema; default if not provided
		if city == "" {
			city = "Unknown"
		}

		// Check if restaurant already exists for this owner
		existing, _ := h.appwrite.GetRestaurantByOwner(userID)
		if existing != nil && existing.Total > 0 {
			// Update existing restaurant
			restID, _ := existing.Documents[0]["$id"].(string)
			restUpdate := map[string]interface{}{
				"name":    restaurantName,
				"address": restaurantAddress,
				"city":    city,
			}
			if cuisineType != "" {
				restUpdate["cuisines"] = []string{cuisineType}
			}
			if latitude != 0 {
				restUpdate["latitude"] = latitude
			}
			if longitude != 0 {
				restUpdate["longitude"] = longitude
			}
			h.appwrite.UpdateRestaurant(restID, restUpdate)
			log.Printf("Onboard: updated existing restaurant %s for user %s", restID, userID)
		} else {
			// Create new restaurant
			restData := map[string]interface{}{
				"owner_id":  userID,
				"name":      restaurantName,
				"address":   restaurantAddress,
				"city":      city,
				"is_online": false,
				"rating":    0.0,
			}
			if cuisineType != "" {
				restData["cuisines"] = []string{cuisineType}
			}
			if latitude != 0 {
				restData["latitude"] = latitude
			}
			if longitude != 0 {
				restData["longitude"] = longitude
			}

			restID := fmt.Sprintf("rest_%s", userID[:8])
			_, createErr := h.appwrite.CreateRestaurant(restID, restData)
			if createErr != nil {
				log.Printf("Onboard: failed to create restaurant: %v", createErr)
				utils.InternalError(c, "Failed to create restaurant")
				return
			}
			log.Printf("Onboard: created restaurant %s for user %s", restID, userID)
		}

	case "delivery_partner":
		vehicleType, _ := req["vehicle_type"].(string)
		vehicleNumber, _ := req["vehicle_number"].(string)

		// Check if delivery partner profile exists
		existing, _ := h.appwrite.GetDeliveryPartner(userID)
		if existing != nil && existing.Total > 0 {
			// Update existing profile
			partnerID, _ := existing.Documents[0]["$id"].(string)
			partnerUpdate := map[string]interface{}{
				"name": name,
			}
			if vehicleType != "" {
				partnerUpdate["vehicle_type"] = vehicleType
			}
			if vehicleNumber != "" {
				partnerUpdate["vehicle_number"] = vehicleNumber
			}
			h.appwrite.UpdateDeliveryPartner(partnerID, partnerUpdate)
			log.Printf("Onboard: updated delivery partner %s for user %s", partnerID, userID)
		} else {
			// Create new delivery partner profile
			// Only use fields that exist in the delivery_partners collection schema
			partnerData := map[string]interface{}{
				"user_id":   userID,
				"name":      name,
				"phone":     "",
				"is_online": false,
				"rating":    4.5,
			}
			if vehicleType != "" {
				partnerData["vehicle_type"] = vehicleType
			} else {
				partnerData["vehicle_type"] = "bike"
			}
			if vehicleNumber != "" {
				partnerData["vehicle_number"] = vehicleNumber
			}

			// Try to get phone from user doc
			user, _ := h.appwrite.GetUser(userID)
			if user != nil {
				if phone, ok := user["phone"].(string); ok {
					partnerData["phone"] = phone
				}
			}

			partnerID := fmt.Sprintf("dp_%s", userID[:8])
			_, createErr := h.appwrite.CreateDeliveryPartner(partnerID, partnerData)
			if createErr != nil {
				log.Printf("Onboard: failed to create delivery partner: %v", createErr)
				utils.InternalError(c, "Failed to create delivery partner profile")
				return
			}
			log.Printf("Onboard: created delivery partner %s for user %s", partnerID, userID)
		}
	}

	utils.Success(c, gin.H{
		"message": "Onboarding complete",
		"role":    role,
	})
}
