package handlers

import (
	"fmt"
	"strings"

	"github.com/chizze/backend/internal/middleware"
	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/pkg/utils"
	"github.com/gin-gonic/gin"
)

// Allowed fields for profile update
var allowedProfileFields = map[string]bool{
	"name":               true,
	"email":              true,
	"phone":              true,
	"avatar_url":         true,
	"address":            true,
	"latitude":           true,
	"longitude":          true,
	"is_veg":             true,
	"dark_mode":          true,
	"default_address_id": true,
}

// UserHandler handles user profile and address endpoints
type UserHandler struct {
	appwrite *services.AppwriteService
	cache    *services.CacheService
}

// NewUserHandler creates a user handler
func NewUserHandler(aw *services.AppwriteService, cache *services.CacheService) *UserHandler {
	return &UserHandler{appwrite: aw, cache: cache}
}

// GetProfile returns current user profile
// @Summary Get current user profile
// @Description Returns the authenticated user's profile information
// @Tags Users
// @Produce json
// @Security BearerAuth
// @Success 200 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/v1/users/me [get]
func (h *UserHandler) GetProfile(c *gin.Context) {
	userID := middleware.GetUserID(c)
	if userID == "" {
		utils.Unauthorized(c, "Authentication required")
		return
	}

	// Try cache first
	var cached map[string]interface{}
	if found, _ := h.cache.GetJSON(c.Request.Context(), services.UserProfileKey(userID), &cached); found {
		utils.Success(c, cached)
		return
	}

	user, err := h.appwrite.GetUser(userID)
	if err != nil {
		utils.InternalError(c, "Failed to fetch profile")
		return
	}

	_ = h.cache.SetJSON(c.Request.Context(), services.UserProfileKey(userID), user, services.UserProfileTTL)
	utils.Success(c, user)
}

// UpdateProfile updates current user profile with field whitelist
// @Summary Update current user profile
// @Description Updates the authenticated user's profile. Allowed fields: name, email, phone, avatar_url, role, address, latitude, longitude.
// @Tags Users
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param request body object true "Profile fields to update"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/v1/users/me [put]
func (h *UserHandler) UpdateProfile(c *gin.Context) {
	userID := middleware.GetUserID(c)
	if userID == "" {
		utils.Unauthorized(c, "Authentication required")
		return
	}

	var req map[string]interface{}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}

	// Filter to only allowed fields
	filtered := make(map[string]interface{})
	for k, v := range req {
		if allowedProfileFields[k] {
			filtered[k] = v
		}
	}
	if len(filtered) == 0 {
		utils.BadRequest(c, "No valid fields to update")
		return
	}

	updated, err := h.appwrite.UpdateUser(userID, filtered)
	if err != nil {
		utils.InternalError(c, "Failed to update profile")
		return
	}
	h.cache.Invalidate(c.Request.Context(), services.UserProfileKey(userID))
	utils.Success(c, updated)
}

// ListAddresses returns user's saved addresses
// @Summary List user addresses
// @Description Returns the authenticated user's saved addresses
// @Tags Users
// @Produce json
// @Security BearerAuth
// @Success 200 {array} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/v1/users/me/addresses [get]
func (h *UserHandler) ListAddresses(c *gin.Context) {
	userID := middleware.GetUserID(c)
	if userID == "" {
		utils.Unauthorized(c, "Authentication required")
		return
	}
	result, err := h.appwrite.ListAddresses(userID)
	if err != nil {
		utils.InternalError(c, "Failed to fetch addresses")
		return
	}
	utils.Success(c, result.Documents)
}

// CreateAddress adds a new address
// @Summary Create a new address
// @Description Adds a new saved address for the authenticated user
// @Tags Users
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param request body object true "Address data (label, line1, line2, city, state, pincode, latitude, longitude, etc.)"
// @Success 201 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/v1/users/me/addresses [post]
func (h *UserHandler) CreateAddress(c *gin.Context) {
	userID := middleware.GetUserID(c)
	if userID == "" {
		utils.Unauthorized(c, "Authentication required")
		return
	}

	var req map[string]interface{}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Invalid address data")
		return
	}

	// Validate required fields (must match frontend: label, full_address)
	for _, field := range []string{"label", "full_address"} {
		val, ok := req[field]
		if !ok {
			utils.BadRequest(c, fmt.Sprintf("Missing required field: %s", field))
			return
		}
		strVal, isStr := val.(string)
		if !isStr || strings.TrimSpace(strVal) == "" {
			utils.BadRequest(c, fmt.Sprintf("Field %s must be a non-empty string", field))
			return
		}
	}

	// Sanitize string fields — trim whitespace and enforce max lengths
	stringMaxLengths := map[string]int{
		"label": 50, "full_address": 200, "landmark": 100,
	}
	for field, maxLen := range stringMaxLengths {
		val, ok := req[field]
		if !ok {
			continue
		}
		strVal, isStr := val.(string)
		if !isStr {
			continue
		}
		trimmed := strings.TrimSpace(strVal)
		if len(trimmed) > maxLen {
			utils.BadRequest(c, fmt.Sprintf("Field %s exceeds max length of %d", field, maxLen))
			return
		}
		req[field] = trimmed
	}

	req["user_id"] = userID

	doc, err := h.appwrite.CreateAddress("unique()", req)
	if err != nil {
		utils.InternalError(c, "Failed to create address")
		return
	}
	utils.Created(c, doc)
}

// UpdateAddress updates an existing address with ownership check
// @Summary Update an existing address
// @Description Updates a saved address after verifying ownership
// @Tags Users
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param id path string true "Address ID"
// @Param request body object true "Updated address data"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Failure 403 {object} map[string]interface{}
// @Failure 404 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/v1/users/me/addresses/{id} [put]
func (h *UserHandler) UpdateAddress(c *gin.Context) {
	userID := middleware.GetUserID(c)
	if userID == "" {
		utils.Unauthorized(c, "Authentication required")
		return
	}
	addrID := c.Param("id")

	// Verify ownership
	addr, err := h.appwrite.GetAddress(addrID)
	if err != nil {
		utils.NotFound(c, "Address not found")
		return
	}
	ownerID, _ := addr["user_id"].(string)
	if ownerID != userID {
		utils.Forbidden(c, "Access denied")
		return
	}

	var req map[string]interface{}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Invalid address data")
		return
	}
	// Prevent changing user_id
	delete(req, "user_id")

	// Sanitize present string fields
	stringMaxLengths := map[string]int{
		"label": 50, "full_address": 200, "landmark": 100,
	}
	for field, maxLen := range stringMaxLengths {
		val, ok := req[field]
		if !ok {
			continue
		}
		strVal, isStr := val.(string)
		if !isStr {
			continue
		}
		trimmed := strings.TrimSpace(strVal)
		if len(trimmed) > maxLen {
			utils.BadRequest(c, fmt.Sprintf("Field %s exceeds max length of %d", field, maxLen))
			return
		}
		req[field] = trimmed
	}

	doc, err := h.appwrite.UpdateAddress(addrID, req)
	if err != nil {
		utils.InternalError(c, "Failed to update address")
		return
	}
	utils.Success(c, doc)
}

// DeleteAddress removes an address with ownership check
// @Summary Delete an address
// @Description Deletes a saved address after verifying ownership
// @Tags Users
// @Produce json
// @Security BearerAuth
// @Param id path string true "Address ID"
// @Success 200 {object} map[string]interface{} "message"
// @Failure 403 {object} map[string]interface{}
// @Failure 404 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/v1/users/me/addresses/{id} [delete]
func (h *UserHandler) DeleteAddress(c *gin.Context) {
	userID := middleware.GetUserID(c)
	if userID == "" {
		utils.Unauthorized(c, "Authentication required")
		return
	}
	addrID := c.Param("id")

	// Verify ownership
	addr, err := h.appwrite.GetAddress(addrID)
	if err != nil {
		utils.NotFound(c, "Address not found")
		return
	}
	ownerID, _ := addr["user_id"].(string)
	if ownerID != userID {
		utils.Forbidden(c, "Access denied")
		return
	}

	if err := h.appwrite.DeleteAddress(addrID); err != nil {
		utils.InternalError(c, "Failed to delete address")
		return
	}
	utils.Success(c, gin.H{"message": "Address deleted"})
}

// UpdateFCMToken updates the user's FCM token for push notifications
// @Summary Update FCM token
// @Description Updates the user's Firebase Cloud Messaging token for push notifications
// @Tags Users
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param request body object true "JSON with token (string, required)"
// @Success 200 {object} map[string]interface{} "message"
// @Failure 400 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/v1/users/me/fcm-token [put]
func (h *UserHandler) UpdateFCMToken(c *gin.Context) {
	userID := middleware.GetUserID(c)
	if userID == "" {
		utils.Unauthorized(c, "Authentication required")
		return
	}

	var req struct {
		Token string `json:"token" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "FCM token is required")
		return
	}

	_, err := h.appwrite.UpdateUser(userID, map[string]interface{}{
		"fcm_token": req.Token,
	})
	if err != nil {
		utils.InternalError(c, "Failed to update FCM token")
		return
	}
	utils.Success(c, gin.H{"message": "FCM token updated"})
}
