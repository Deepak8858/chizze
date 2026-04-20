package handlers

import (
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/chizze/backend/internal/config"
	"github.com/chizze/backend/internal/middleware"
	"github.com/chizze/backend/internal/models"
	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/pkg/appwrite"
	redispkg "github.com/chizze/backend/pkg/redis"
	"github.com/chizze/backend/pkg/utils"
	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

// safeIDSuffix returns a short, filesystem-safe suffix derived from a user ID.
// Safe against IDs shorter than the requested length (no slice panic).
func safeIDSuffix(id string, n int) string {
	if len(id) <= n {
		return id
	}
	return id[:n]
}

// AuthHandler handles authentication endpoints
type AuthHandler struct {
	appwrite *services.AppwriteService
	redis    *redispkg.Client
	cfg      *config.Config
}

const (
	authCookieName          = "chizze_auth_token"
	authCookieMaxAgeSeconds = 90 * 24 * 60 * 60
)

// NewAuthHandler creates an auth handler
func NewAuthHandler(aw *services.AppwriteService, redis *redispkg.Client, cfg *config.Config) *AuthHandler {
	return &AuthHandler{appwrite: aw, redis: redis, cfg: cfg}
}

func (h *AuthHandler) setAuthCookie(c *gin.Context, token string) {
	isHTTPS := c.Request.TLS != nil || strings.EqualFold(c.GetHeader("X-Forwarded-Proto"), "https")
	secure := h.cfg.IsProduction() || isHTTPS

	c.SetSameSite(http.SameSiteLaxMode)
	c.SetCookie(authCookieName, token, authCookieMaxAgeSeconds, "/", "", secure, true)
}

func (h *AuthHandler) clearAuthCookie(c *gin.Context) {
	isHTTPS := c.Request.TLS != nil || strings.EqualFold(c.GetHeader("X-Forwarded-Proto"), "https")
	secure := h.cfg.IsProduction() || isHTTPS

	c.SetSameSite(http.SameSiteLaxMode)
	c.SetCookie(authCookieName, "", -1, "/", "", secure, true)
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

// roleDisplayName maps internal role strings to user-friendly display names.
func roleDisplayName(role string) string {
	switch role {
	case "restaurant_owner":
		return "Restaurant Partner"
	case "delivery_partner":
		return "Delivery Partner"
	case "customer":
		return "Customer"
	default:
		return role
	}
}

func boolFromSetting(value interface{}, defaultValue bool) bool {
	switch v := value.(type) {
	case bool:
		return v
	case string:
		parsed, err := strconv.ParseBool(strings.TrimSpace(v))
		if err == nil {
			return parsed
		}
	case float64:
		return v != 0
	case int:
		return v != 0
	}
	return defaultValue
}

func (h *AuthHandler) isPartnerSignupAllowed(role string) bool {
	if role != "restaurant_owner" && role != "delivery_partner" {
		return true
	}

	settings, err := h.appwrite.ListDocuments(models.CollectionSettings, []string{
		appwrite.QueryLimit(1),
	})
	if err != nil {
		// Default-allow: settings collection is optional admin-override. A missing
		// collection (404) or transient Appwrite error must NOT permanently lock
		// partner signup — a fresh deployment has no settings doc at all.
		log.Printf("[WARN] isPartnerSignupAllowed: ListDocuments(settings) failed, default-allow: %v", err)
		return true
	}
	if settings == nil || len(settings.Documents) == 0 {
		// No admin override configured — allow partner signup by default.
		return true
	}

	doc := settings.Documents[0]
	if role == "restaurant_owner" {
		return boolFromSetting(doc["allow_restaurant_partner_signup"], false)
	}
	return boolFromSetting(doc["allow_delivery_partner_signup"], false)
}

func partnerSignupDisabledMessage(role string) string {
	return "New " + roleDisplayName(role) + " signups are currently disabled by admin"
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

	ctx := c.Request.Context()

	// Validate the Appwrite JWT by calling Appwrite GET /account
	account, err := h.appwrite.Client().VerifyJWTCtx(ctx, req.AppwriteJWT)
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

	phone, _ := account["phone"].(string)

	// ─── Check if user exists in our users collection ───
	// Use typed errors to distinguish "not found" from transient Appwrite failures.
	// Returning a generic error on transient failures is critical: swallowing them
	// would cause the returning-user path to mis-fire as new-user creation.
	user, err := h.appwrite.GetUser(appwriteUserID)
	if err != nil && !appwrite.IsNotFound(err) {
		log.Printf("[ERROR] Exchange: GetUser(%s) transient failure: %v", appwriteUserID, err)
		utils.Error(c, http.StatusServiceUnavailable, "Our servers are temporarily unavailable. Please try again in a moment.")
		return
	}

	role := "customer" // default role
	isNew := false

	if user == nil {
		// Acquire a short Redis lock keyed on phone to prevent two concurrent
		// Exchange calls for the same phone from both migrating/creating docs
		// and racing each other into a corrupted state.
		if phone != "" && h.redis != nil {
			lockKey := "auth_phone_lock:" + phone
			acquired, lockErr := h.redis.SetNX(ctx, lockKey, "1", 10*time.Second)
			if lockErr == nil && !acquired {
				utils.Error(c, http.StatusConflict, "Another sign-in is in progress for this number. Please try again in a moment.")
				return
			}
			if lockErr == nil {
				defer func() { _ = h.redis.Del(ctx, lockKey) }()
			}
		}

		// Re-check after acquiring the lock: the other winner may have just created the doc.
		if recheck, rerr := h.appwrite.GetUser(appwriteUserID); rerr == nil && recheck != nil {
			user = recheck
		}
	}

	if user == nil {
		// Still no doc for this Appwrite user ID.
		// Appwrite may create a new user account (new ID) on each phone login,
		// so check if there's an existing doc for this phone number.
		var existingDoc map[string]interface{}
		if phone != "" {
			existingUsers, lookupErr := h.appwrite.ListUsers([]string{
				appwrite.QueryEqual("phone", phone),
				appwrite.QueryLimit(1),
			})
			if lookupErr != nil {
				log.Printf("[ERROR] Exchange: ListUsers(phone=%s) failed: %v", phone, lookupErr)
				utils.Error(c, http.StatusServiceUnavailable, "Our servers are temporarily unavailable. Please try again in a moment.")
				return
			}
			if existingUsers != nil && existingUsers.Total > 0 {
				existingDoc = existingUsers.Documents[0]
			}
		}

		if existingDoc != nil {
			// Found existing doc with same phone but different Appwrite user ID.
			oldID, _ := existingDoc["$id"].(string)
			if r, ok := existingDoc["role"].(string); ok && r != "" {
				role = r
			}
			// Cross-role guard: if existing doc has a role and client wants a
			// different role, reject instead of migrating with a new role.
			if req.Role != "" && req.Role != role {
				utils.Error(c, 409, "This phone number is already registered as "+roleDisplayName(role)+". Please use a different number.")
				return
			}

			// Migrate: create new doc FIRST with current Appwrite user ID, then delete old.
			// Creating-then-deleting means a crash mid-migration leaves a duplicate
			// (recoverable) instead of deleting the only copy (unrecoverable data loss).
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

			if _, createErr := h.appwrite.CreateUser(appwriteUserID, migratedData); createErr != nil {
				// If the new doc already exists (conflict), treat as success — we raced
				// another Exchange call and it already migrated the doc.
				if !appwrite.IsConflict(createErr) {
					log.Printf("[ERROR] Exchange: migration create failed for %s (phone=%s): %v", appwriteUserID, phone, createErr)
					utils.InternalError(c, "Failed to create user profile. Please try again.")
					return
				}
				log.Printf("Exchange: migration create conflict for %s — another request completed the migration", appwriteUserID)
			}
			// Delete old doc only after new doc is safely persisted.
			if deleteErr := h.appwrite.DeleteUser(oldID); deleteErr != nil && !appwrite.IsNotFound(deleteErr) {
				// Non-fatal: the new doc is valid. Log and continue.
				log.Printf("[WARN] Exchange: delete old migrated doc %s failed: %v", oldID, deleteErr)
			}
			log.Printf("Exchange: migrated user doc from %s to %s (phone=%s)", oldID, appwriteUserID, phone)
			isNew = false
		} else {
			// Truly new user — no existing doc for this phone
			isNew = true
			email, _ := account["email"].(string)
			name, _ := account["name"].(string)

			if req.Role != "" {
				role = req.Role
			}
			if !h.isPartnerSignupAllowed(role) {
				utils.Error(c, 403, partnerSignupDisabledMessage(role))
				return
			}

			userData := map[string]interface{}{
				"phone": phone,
				"name":  name,
				"role":  role,
			}
			if email != "" {
				userData["email"] = email
			}
			if _, createErr := h.appwrite.CreateUser(appwriteUserID, userData); createErr != nil {
				// Conflict means the doc was just created by a concurrent Exchange — ok.
				if !appwrite.IsConflict(createErr) {
					log.Printf("[ERROR] Exchange: CreateUser(%s) failed: %v", appwriteUserID, createErr)
					utils.InternalError(c, "Failed to create user profile. Please try again.")
					return
				}
				log.Printf("Exchange: CreateUser conflict for %s — treating as returning user", appwriteUserID)
				// Fetch the just-created doc so we return its role
				if refetched, ferr := h.appwrite.GetUser(appwriteUserID); ferr == nil && refetched != nil {
					if r, ok := refetched["role"].(string); ok && r != "" {
						role = r
					}
					isNew = false
				}
			}
		}
	} else {
		// Existing user — read role
		if r, ok := user["role"].(string); ok && r != "" {
			role = r
		}
		// Cross-role guard: prevent the same account from switching roles.
		// If the client sent a role and it doesn't match what's stored, reject.
		if req.Role != "" && req.Role != role {
			utils.Error(c, 409, "This phone number is already registered as "+roleDisplayName(role)+". Please use a different number.")
			return
		}
	}

	// For returning users, verify onboarding was actually completed.
	// If the role-specific record is missing, force onboarding.
	// ALL roles must have a non-empty name and phone in users collection — OAuth
	// providers (Google/Apple/Facebook) frequently omit name, so we cannot trust
	// the doc just exists. (Fixes signup-without-name bug.)
	{
		needsOnboarding := false
		// Profile completeness check applies to every role.
		checkUser := user
		if checkUser == nil {
			checkUser, _ = h.appwrite.GetUser(appwriteUserID)
		}
		if checkUser != nil {
			userName, _ := checkUser["name"].(string)
			userPhone, _ := checkUser["phone"].(string)
			if userName == "" || userPhone == "" {
				needsOnboarding = true
			}
		}
		if !needsOnboarding && !isNew {
			switch role {
			case "restaurant_owner":
				existing, lookupErr := h.appwrite.GetRestaurantByOwner(appwriteUserID)
				// Only flag as missing when we confirmed empty; transient errors are ignored
				// (prevents spurious re-onboarding when Appwrite is flaky).
				if lookupErr == nil && (existing == nil || existing.Total == 0) {
					needsOnboarding = true
				}
			case "delivery_partner":
				existing, lookupErr := h.appwrite.GetDeliveryPartner(appwriteUserID)
				if lookupErr == nil && (existing == nil || existing.Total == 0) {
					needsOnboarding = true
				}
			}
		}
		if needsOnboarding {
			isNew = true
			log.Printf("User %s (role=%s) incomplete profile — marking as new for onboarding", appwriteUserID, role)
		}
	}

	// Clear any previous token blacklist so the new session works.
	// Logout blacklists by userID — re-login must clear it.
	if err := h.redis.Del(ctx, "token_blacklist:"+appwriteUserID); err != nil {
		log.Printf("[WARN] Exchange: failed to clear blacklist for %s: %v", appwriteUserID, err)
	}

	// Issue our JWT (valid for 90 days — users stay logged in until explicit logout)
	token, err := h.issueJWT(appwriteUserID, role, 90*24*time.Hour)
	if err != nil {
		utils.InternalError(c, "Failed to generate token")
		return
	}

	h.setAuthCookie(c, token)

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
	ctx := c.Request.Context()
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
		// Optional role selected at signup. Must match Exchange's behavior so
		// partners/riders aren't silently downgraded to "customer" when they
		// enter the app through the OTP path instead of Exchange.
		Role string `json:"role"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Phone, OTP, and appwrite_jwt are required")
		return
	}

	ctx := c.Request.Context()

	// Validate the Appwrite JWT to prove OTP was actually verified on client
	account, err := h.appwrite.Client().VerifyJWTCtx(ctx, req.AppwriteJWT)
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

	// Check if user exists — must distinguish not-found from transient failure,
	// otherwise an Appwrite blip silently creates a duplicate user with default role.
	user, err := h.appwrite.GetUser(appwriteUserID)
	if err != nil && !appwrite.IsNotFound(err) {
		log.Printf("[ERROR] VerifyOTP: GetUser(%s) transient failure: %v", appwriteUserID, err)
		utils.Error(c, http.StatusServiceUnavailable, "Our servers are temporarily unavailable. Please try again in a moment.")
		return
	}

	role := "customer"
	if user == nil {
		// Honor the client-selected role for new users. Validate it's one of
		// the allowed values and that partner signup is currently enabled.
		if req.Role != "" {
			switch req.Role {
			case "customer", "restaurant_owner", "delivery_partner":
				role = req.Role
			default:
				utils.BadRequest(c, "Invalid role selected")
				return
			}
		}
		if !h.isPartnerSignupAllowed(role) {
			utils.Error(c, http.StatusForbidden, partnerSignupDisabledMessage(role))
			return
		}
		// Create user with all required fields. We MUST surface failures — if
		// we silently ignore them, the client receives a JWT but every subsequent
		// /users/me etc. request will 404 because no user doc exists.
		userData := map[string]interface{}{
			"name":  "",
			"phone": req.Phone,
			"role":  role,
		}
		if _, createErr := h.appwrite.CreateUser(appwriteUserID, userData); createErr != nil && !appwrite.IsConflict(createErr) {
			log.Printf("[ERROR] VerifyOTP: CreateUser(%s) failed: %v", appwriteUserID, createErr)
			utils.InternalError(c, "Failed to create user profile. Please try again.")
			return
		}
	} else {
		if r, ok := user["role"].(string); ok && r != "" {
			role = r
		}
		// Cross-role guard: if an existing user tries to sign in with a
		// different role, reject with a clear message.
		if req.Role != "" && req.Role != role {
			utils.Error(c, http.StatusConflict,
				"This phone number is already registered as "+roleDisplayName(role)+
					". Please use a different number.")
			return
		}
	}

	// Clear any previous token blacklist so the new session works
	if err := h.redis.Del(ctx, "token_blacklist:"+appwriteUserID); err != nil {
		log.Printf("[WARN] VerifyOTP: failed to clear blacklist for %s: %v", appwriteUserID, err)
	}

	token, err := h.issueJWT(appwriteUserID, role, 90*24*time.Hour)
	if err != nil {
		utils.InternalError(c, "Failed to generate token")
		return
	}

	h.setAuthCookie(c, token)

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
	ctx := c.Request.Context()
	blacklisted, _ := h.redis.Exists(ctx, "token_blacklist:"+userID)
	if blacklisted {
		utils.Unauthorized(c, "Token has been revoked")
		return
	}

	// Issue new token (90 days)
	token, err := h.issueJWT(userID, role, 90*24*time.Hour)
	if err != nil {
		utils.InternalError(c, "Failed to refresh token")
		return
	}

	h.setAuthCookie(c, token)

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
	h.clearAuthCookie(c)

	userID := middleware.GetUserID(c)
	if userID == "" {
		utils.Success(c, gin.H{"message": "Logged out"})
		return
	}

	// Blacklist the user's tokens for the remainder of the JWT TTL (90 days)
	ctx := c.Request.Context()
	if err := h.redis.Set(ctx, "token_blacklist:"+userID, "1", 90*24*time.Hour); err != nil {
		log.Printf("[WARN] Logout: failed to blacklist token for %s: %v", userID, err)
	}

	utils.Success(c, gin.H{"message": "Logged out successfully"})
}

// CheckPhone checks if a phone number is already registered
// @Summary Check if phone is registered
// @Description Checks whether a phone number exists in the users collection
// @Tags Auth
// @Accept json
// @Produce json
// @Param request body object true "JSON with phone (string, required)"
// @Success 200 {object} map[string]interface{} "exists (bool), role (string, if exists)"
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
		role, _ := result.Documents[0]["role"].(string)
		utils.Success(c, gin.H{
			"exists": true,
			"role":   role,
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
	if !h.isPartnerSignupAllowed(role) {
		utils.Error(c, 403, partnerSignupDisabledMessage(role))
		return
	}

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
	phone, _ := req["phone"].(string)
	address, _ := req["address"].(string)
	latitude, _ := req["latitude"].(float64)
	longitude, _ := req["longitude"].(float64)

	if name == "" {
		utils.BadRequest(c, "Name is required")
		return
	}

	// Customers must share their current location to receive deliveries.
	// We enforce this on the backend so it cannot be bypassed by a modified client.
	if role == "customer" && (latitude == 0 || longitude == 0) {
		utils.BadRequest(c, "Your current location is required to set up your account. Please enable location access and try again.")
		return
	}

	// Update user profile
	userUpdate := map[string]interface{}{
		"name": name,
	}
	if email != "" {
		userUpdate["email"] = email
	}
	if phone != "" {
		userUpdate["phone"] = phone
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
	// Save preference fields from onboarding
	if isVeg, ok := req["is_veg"].(bool); ok {
		userUpdate["is_veg"] = isVeg
	}
	if darkMode, ok := req["dark_mode"].(bool); ok {
		userUpdate["dark_mode"] = darkMode
	}

	_, err := h.appwrite.UpdateUser(userID, userUpdate)
	if err != nil && !appwrite.IsNotFound(err) {
		// Transient/Appwrite error (not a clean 404). Don't fall into the
		// create-if-missing branch because we'd silently overwrite an existing
		// user's phone with "" if the error was not really a not-found.
		log.Printf("[ERROR] Onboard: UpdateUser(%s) transient failure: %v", userID, err)
		utils.Error(c, http.StatusServiceUnavailable, "Our servers are temporarily unavailable. Please try again in a moment.")
		return
	}
	if err != nil {
		log.Printf("Onboard: UpdateUser not-found for %s — attempting create", userID)
		// User doc is genuinely missing (e.g. if creation failed during login).
		// Build a complete user doc with all required fields and create it.
		createData := map[string]interface{}{
			"name":  name,
			"phone": phone,
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
		if isVeg, ok := req["is_veg"].(bool); ok {
			createData["is_veg"] = isVeg
		}
		if darkMode, ok := req["dark_mode"].(bool); ok {
			createData["dark_mode"] = darkMode
		}
		_, createErr := h.appwrite.CreateUser(userID, createData)
		if createErr != nil && !appwrite.IsConflict(createErr) {
			log.Printf("[ERROR] Onboard: CreateUser(%s) failed: %v", userID, createErr)
			utils.InternalError(c, "Failed to update profile. Please try again.")
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

		// Check if restaurant already exists for this owner. A transient lookup
		// failure must not silently fall through to create-new — that would leave
		// the owner with duplicate restaurants.
		existing, lookupErr := h.appwrite.GetRestaurantByOwner(userID)
		if lookupErr != nil && !appwrite.IsNotFound(lookupErr) {
			log.Printf("[ERROR] Onboard: GetRestaurantByOwner(%s) failed: %v", userID, lookupErr)
			utils.Error(c, http.StatusServiceUnavailable, "Our servers are temporarily unavailable. Please try again in a moment.")
			return
		}
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
			if _, updateErr := h.appwrite.UpdateRestaurant(restID, restUpdate); updateErr != nil {
				log.Printf("[ERROR] Onboard: UpdateRestaurant(%s) failed: %v", restID, updateErr)
				utils.InternalError(c, "Failed to update restaurant. Please try again.")
				return
			}
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

			restID := fmt.Sprintf("rest_%s", safeIDSuffix(userID, 8))
			_, createErr := h.appwrite.CreateRestaurant(restID, restData)
			if createErr != nil && !appwrite.IsConflict(createErr) {
				log.Printf("[ERROR] Onboard: CreateRestaurant(%s) failed: %v", restID, createErr)
				utils.InternalError(c, "Failed to create restaurant. Please try again.")
				return
			}
			log.Printf("Onboard: created restaurant %s for user %s", restID, userID)
		}

	case "delivery_partner":
		vehicleType, _ := req["vehicle_type"].(string)
		vehicleNumber, _ := req["vehicle_number"].(string)

		// Check if delivery partner profile exists
		existing, lookupErr := h.appwrite.GetDeliveryPartner(userID)
		if lookupErr != nil && !appwrite.IsNotFound(lookupErr) {
			log.Printf("[ERROR] Onboard: GetDeliveryPartner(%s) failed: %v", userID, lookupErr)
			utils.Error(c, http.StatusServiceUnavailable, "Our servers are temporarily unavailable. Please try again in a moment.")
			return
		}
		if existing != nil && existing.Total > 0 {
			// Update existing profile
			partnerID, _ := existing.Documents[0]["$id"].(string)
			partnerUpdate := map[string]interface{}{}
			if vehicleType != "" {
				partnerUpdate["vehicle_type"] = vehicleType
			}
			if vehicleNumber != "" {
				partnerUpdate["vehicle_number"] = vehicleNumber
			}
			if len(partnerUpdate) > 0 {
				if _, updateErr := h.appwrite.UpdateDeliveryPartner(partnerID, partnerUpdate); updateErr != nil {
					log.Printf("[ERROR] Onboard: UpdateDeliveryPartner(%s) failed: %v", partnerID, updateErr)
					utils.InternalError(c, "Failed to update delivery partner profile. Please try again.")
					return
				}
			}
			log.Printf("Onboard: updated delivery partner %s for user %s", partnerID, userID)
		} else {
			// Create new delivery partner profile. Stored fields mirror the
			// delivery_partners collection schema (user_id, vehicle_type, etc.);
			// name/phone live in users.
			partnerData := map[string]interface{}{
				"user_id":        userID,
				"is_online":      false,
				"is_on_delivery": false,
				"rating":         4.5,
			}
			if vehicleType != "" {
				partnerData["vehicle_type"] = vehicleType
			} else {
				partnerData["vehicle_type"] = "bike"
			}
			if vehicleNumber != "" {
				partnerData["vehicle_number"] = vehicleNumber
			}

			partnerID := fmt.Sprintf("dp_%s", safeIDSuffix(userID, 8))
			_, createErr := h.appwrite.CreateDeliveryPartner(partnerID, partnerData)
			if createErr != nil && !appwrite.IsConflict(createErr) {
				log.Printf("[ERROR] Onboard: CreateDeliveryPartner(%s) failed: %v", partnerID, createErr)
				utils.InternalError(c, "Failed to create delivery partner profile. Please try again.")
				return
			}
			log.Printf("Onboard: created delivery partner %s for user %s", partnerID, userID)
		}
	}

	// Invalidate the user profile cache so the next GET /users/me returns the
	// just-saved name/phone/address instead of a stale pre-onboarding snapshot.
	// Why: main.dart watches userProfileProvider at the app root, so the client
	// fetches the profile as soon as the session turns authenticated — which
	// populates the Redis cache BEFORE onboarding runs. Without this Del, the
	// post-onboarding refetch reads back the empty-name snapshot and the
	// profile tab shows "Set up your profile" instead of the entered name.
	if err := h.redis.Del(c.Request.Context(), services.UserProfileKey(userID)); err != nil {
		log.Printf("[WARN] Onboard: failed to invalidate profile cache for %s: %v", userID, err)
	}

	// Fetch updated user doc to return to client
	updatedUser, _ := h.appwrite.GetUser(userID)

	utils.Success(c, gin.H{
		"message": "Onboarding complete",
		"role":    role,
		"user":    updatedUser,
	})
}
