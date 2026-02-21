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

// getPartnerRestaurant looks up the restaurant owned by the current user
func (h *MenuHandler) getPartnerRestaurant(c *gin.Context) (map[string]interface{}, string, bool) {
	userID := middleware.GetUserID(c)
	result, err := h.appwrite.GetRestaurantByOwner(userID)
	if err != nil || result == nil || len(result.Documents) == 0 {
		utils.Forbidden(c, "No restaurant found for this partner")
		return nil, "", false
	}
	restaurant := result.Documents[0]
	restID, _ := restaurant["$id"].(string)
	return restaurant, restID, true
}

// verifyItemOwnership checks that a menu item belongs to the partner's restaurant
func (h *MenuHandler) verifyItemOwnership(c *gin.Context, itemID, restaurantID string) (map[string]interface{}, bool) {
	item, err := h.appwrite.GetMenuItem(itemID)
	if err != nil {
		utils.NotFound(c, "Menu item not found")
		return nil, false
	}
	itemRestID, _ := item["restaurant_id"].(string)
	if itemRestID != restaurantID {
		utils.Forbidden(c, "This item does not belong to your restaurant")
		return nil, false
	}
	return item, true
}

// ListItems returns partner's menu items
// GET /api/v1/partner/menu
func (h *MenuHandler) ListItems(c *gin.Context) {
	_, restID, ok := h.getPartnerRestaurant(c)
	if !ok {
		return
	}

	items, err := h.appwrite.ListMenuItems(restID)
	if err != nil {
		utils.InternalError(c, "Failed to fetch menu items")
		return
	}
	utils.Success(c, gin.H{"items": items.Documents, "total": items.Total})
}

// CreateItem adds a new menu item for the partner's restaurant
// POST /api/v1/partner/menu
func (h *MenuHandler) CreateItem(c *gin.Context) {
	_, restID, ok := h.getPartnerRestaurant(c)
	if !ok {
		return
	}

	var req map[string]interface{}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Invalid menu item data")
		return
	}

	// Validate required fields
	name, _ := req["name"].(string)
	price, hasPrice := req["price"].(float64)
	if name == "" || !hasPrice || price < 0 {
		utils.BadRequest(c, "name and price (>= 0) are required")
		return
	}

	// Force restaurant_id to partner's restaurant
	req["restaurant_id"] = restID
	if _, ok := req["is_available"]; !ok {
		req["is_available"] = true
	}

	doc, err := h.appwrite.CreateMenuItem("unique()", req)
	if err != nil {
		utils.InternalError(c, "Failed to create menu item")
		return
	}
	utils.Created(c, doc)
}

// UpdateItem updates an existing menu item with ownership check
// PUT /api/v1/partner/menu/:id
func (h *MenuHandler) UpdateItem(c *gin.Context) {
	_, restID, ok := h.getPartnerRestaurant(c)
	if !ok {
		return
	}

	itemID := c.Param("id")
	if _, owned := h.verifyItemOwnership(c, itemID, restID); !owned {
		return
	}

	var req map[string]interface{}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Invalid data")
		return
	}

	// Prevent changing restaurant_id
	delete(req, "restaurant_id")
	delete(req, "$id")

	doc, err := h.appwrite.UpdateMenuItem(itemID, req)
	if err != nil {
		utils.InternalError(c, "Failed to update menu item")
		return
	}
	utils.Success(c, doc)
}

// DeleteItem removes a menu item with ownership check
// DELETE /api/v1/partner/menu/:id
func (h *MenuHandler) DeleteItem(c *gin.Context) {
	_, restID, ok := h.getPartnerRestaurant(c)
	if !ok {
		return
	}

	itemID := c.Param("id")
	if _, owned := h.verifyItemOwnership(c, itemID, restID); !owned {
		return
	}

	if err := h.appwrite.DeleteMenuItem(itemID); err != nil {
		utils.InternalError(c, "Failed to delete menu item")
		return
	}
	utils.Success(c, gin.H{"message": "Menu item deleted"})
}
