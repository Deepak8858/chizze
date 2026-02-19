package handlers

import (
	"github.com/chizze/backend/internal/middleware"
	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/pkg/utils"
	"github.com/gin-gonic/gin"
)

// MenuHandler handles partner menu management
type MenuHandler struct {
	appwrite *services.AppwriteService
}

// NewMenuHandler creates a menu handler
func NewMenuHandler(aw *services.AppwriteService) *MenuHandler {
	return &MenuHandler{appwrite: aw}
}

// ListItems returns partner's menu items
// GET /api/v1/partner/menu
func (h *MenuHandler) ListItems(c *gin.Context) {
	_ = middleware.GetUserID(c)
	// TODO: Get restaurant by owner_id, then list menu items
	utils.Success(c, gin.H{"items": []interface{}{}, "message": "Fetch by owner restaurant"})
}

// CreateItem adds a new menu item
// POST /api/v1/partner/menu
func (h *MenuHandler) CreateItem(c *gin.Context) {
	var req map[string]interface{}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Invalid menu item data")
		return
	}

	doc, err := h.appwrite.CreateMenuItem("unique()", req)
	if err != nil {
		utils.InternalError(c, "Failed to create menu item")
		return
	}
	utils.Created(c, doc)
}

// UpdateItem updates an existing menu item
// PUT /api/v1/partner/menu/:id
func (h *MenuHandler) UpdateItem(c *gin.Context) {
	itemID := c.Param("id")
	var req map[string]interface{}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Invalid data")
		return
	}

	doc, err := h.appwrite.UpdateMenuItem(itemID, req)
	if err != nil {
		utils.InternalError(c, "Failed to update menu item")
		return
	}
	utils.Success(c, doc)
}

// DeleteItem removes a menu item
// DELETE /api/v1/partner/menu/:id
func (h *MenuHandler) DeleteItem(c *gin.Context) {
	itemID := c.Param("id")
	if err := h.appwrite.DeleteMenuItem(itemID); err != nil {
		utils.InternalError(c, "Failed to delete menu item")
		return
	}
	utils.Success(c, gin.H{"message": "Menu item deleted"})
}
