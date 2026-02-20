package handlers

import (
	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/pkg/appwrite"
	"github.com/chizze/backend/pkg/utils"
	"github.com/gin-gonic/gin"
)

// RestaurantHandler handles restaurant endpoints
type RestaurantHandler struct {
	appwrite *services.AppwriteService
	geo      *services.GeoService
}

// NewRestaurantHandler creates a restaurant handler
func NewRestaurantHandler(aw *services.AppwriteService, geo *services.GeoService) *RestaurantHandler {
	return &RestaurantHandler{appwrite: aw, geo: geo}
}

// List returns restaurants with search/filter
// GET /api/v1/restaurants
func (h *RestaurantHandler) List(c *gin.Context) {
	queries := []string{appwrite.QueryEqual("is_online", true)}

	if cuisine := c.Query("cuisine"); cuisine != "" {
		queries = append(queries, appwrite.QuerySearch("cuisines", cuisine))
	}

	if c.Query("veg_only") == "true" {
		queries = append(queries, appwrite.QueryEqual("is_veg_only", true))
	}

	result, err := h.appwrite.ListRestaurants(queries)
	if err != nil {
		utils.InternalError(c, "Failed to fetch restaurants")
		return
	}
	utils.Success(c, result.Documents)
}

// Nearby returns restaurants within a radius
// GET /api/v1/restaurants/nearby?lat=X&lng=Y&radius=5
func (h *RestaurantHandler) Nearby(c *gin.Context) {
	// TODO: Parse lat/lng/radius, compute bounding box, filter
	utils.Success(c, gin.H{"message": "Nearby search — implement with geo service"})
}

// GetDetail returns restaurant details
// GET /api/v1/restaurants/:id
func (h *RestaurantHandler) GetDetail(c *gin.Context) {
	id := c.Param("id")
	restaurant, err := h.appwrite.GetRestaurant(id)
	if err != nil {
		utils.NotFound(c, "Restaurant not found")
		return
	}
	utils.Success(c, restaurant)
}

// GetMenu returns restaurant menu grouped by categories
// GET /api/v1/restaurants/:id/menu
func (h *RestaurantHandler) GetMenu(c *gin.Context) {
	restaurantID := c.Param("id")
	items, err := h.appwrite.ListMenuItems(restaurantID)
	if err != nil {
		utils.InternalError(c, "Failed to fetch menu")
		return
	}
	utils.Success(c, items.Documents)
}

// GetReviews returns paginated reviews
// GET /api/v1/restaurants/:id/reviews
func (h *RestaurantHandler) GetReviews(c *gin.Context) {
	restaurantID := c.Param("id")
	reviews, err := h.appwrite.ListReviews(restaurantID)
	if err != nil {
		utils.InternalError(c, "Failed to fetch reviews")
		return
	}
	utils.Success(c, reviews.Documents)
}
