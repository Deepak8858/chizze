package handlers

import (
	"github.com/chizze/backend/internal/middleware"
	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/pkg/utils"
	"github.com/gin-gonic/gin"
)

// Allowed fields for profile update
var allowedProfileFields = map[string]bool{
	"name":          true,
	"email":         true,
	"phone":         true,
	"profile_image": true,
	"role":          true,
	"address":       true,
	"latitude":      true,
	"longitude":     true,
}

// UserHandler handles user profile and address endpoints
type UserHandler struct {
	appwrite *services.AppwriteService
}

// NewUserHandler creates a user handler
func NewUserHandler(aw *services.AppwriteService) *UserHandler {
	return &UserHandler{appwrite: aw}
}

// GetProfile returns current user profile
// GET /api/v1/users/me
func (h *UserHandler) GetProfile(c *gin.Context) {
	userID := middleware.GetUserID(c)
	user, err := h.appwrite.GetUser(userID)
	if err != nil {
		utils.InternalError(c, "Failed to fetch profile")
		return
	}
	utils.Success(c, user)
}

// UpdateProfile updates current user profile with field whitelist
// PUT /api/v1/users/me
func (h *UserHandler) UpdateProfile(c *gin.Context) {
	userID := middleware.GetUserID(c)

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
	utils.Success(c, updated)
}

// ListAddresses returns user's saved addresses
// GET /api/v1/users/me/addresses
func (h *UserHandler) ListAddresses(c *gin.Context) {
	userID := middleware.GetUserID(c)
	result, err := h.appwrite.ListAddresses(userID)
	if err != nil {
		utils.InternalError(c, "Failed to fetch addresses")
		return
	}
	utils.Success(c, result.Documents)
}

// CreateAddress adds a new address
// POST /api/v1/users/me/addresses
func (h *UserHandler) CreateAddress(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req map[string]interface{}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Invalid address data")
		return
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
// PUT /api/v1/users/me/addresses/:id
func (h *UserHandler) UpdateAddress(c *gin.Context) {
	userID := middleware.GetUserID(c)
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

	doc, err := h.appwrite.UpdateAddress(addrID, req)
	if err != nil {
		utils.InternalError(c, "Failed to update address")
		return
	}
	utils.Success(c, doc)
}

// DeleteAddress removes an address with ownership check
// DELETE /api/v1/users/me/addresses/:id
func (h *UserHandler) DeleteAddress(c *gin.Context) {
	userID := middleware.GetUserID(c)
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
