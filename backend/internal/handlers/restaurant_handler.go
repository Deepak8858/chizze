package handlers

import (
	"fmt"
	"strconv"

	"github.com/chizze/backend/internal/models"
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

// List returns restaurants with search/filter/pagination
// GET /api/v1/restaurants
func (h *RestaurantHandler) List(c *gin.Context) {
	pg := models.ParsePagination(c)
	queries := []string{
		appwrite.QueryEqual("is_online", true),
		appwrite.QueryLimit(pg.PerPage),
		appwrite.QueryOffset(pg.Offset()),
	}

	if cuisine := c.Query("cuisine"); cuisine != "" {
		queries = append(queries, appwrite.QuerySearch("cuisines", cuisine))
	}
	if c.Query("veg_only") == "true" {
		queries = append(queries, appwrite.QueryEqual("is_veg_only", true))
	}
	if sort := c.Query("sort"); sort == "rating" {
		queries = append(queries, appwrite.QueryOrderDesc("rating"))
	}

	result, err := h.appwrite.ListRestaurants(queries)
	if err != nil {
		utils.InternalError(c, "Failed to fetch restaurants")
		return
	}
	utils.Paginated(c, result.Documents, pg.Page, pg.PerPage, result.Total)
}

// Nearby returns restaurants within a radius using geo bounding box + Haversine
// GET /api/v1/restaurants/nearby?lat=X&lng=Y&radius=5
func (h *RestaurantHandler) Nearby(c *gin.Context) {
	lat, err := strconv.ParseFloat(c.Query("lat"), 64)
	if err != nil {
		utils.BadRequest(c, "Valid latitude is required")
		return
	}
	lng, err := strconv.ParseFloat(c.Query("lng"), 64)
	if err != nil {
		utils.BadRequest(c, "Valid longitude is required")
		return
	}
	radius := 5.0 // default 5km
	if r, err := strconv.ParseFloat(c.Query("radius"), 64); err == nil && r > 0 && r <= 50 {
		radius = r
	}

	// Compute bounding box for efficient DB query
	minLat, maxLat, minLng, maxLng := h.geo.NearbyBounds(lat, lng, radius)

	queries := []string{
		appwrite.QueryEqual("is_online", true),
		appwrite.QueryGreaterThanEqual("latitude", fmt.Sprintf("%f", minLat)),
		appwrite.QueryLessThanEqual("latitude", fmt.Sprintf("%f", maxLat)),
		appwrite.QueryGreaterThanEqual("longitude", fmt.Sprintf("%f", minLng)),
		appwrite.QueryLessThanEqual("longitude", fmt.Sprintf("%f", maxLng)),
		appwrite.QueryLimit(100),
	}

	result, err := h.appwrite.ListRestaurants(queries)
	if err != nil {
		utils.InternalError(c, "Failed to fetch nearby restaurants")
		return
	}

	// Haversine refinement — filter to actual radius and add distance
	nearby := make([]map[string]interface{}, 0)
	for _, doc := range result.Documents {
		rLat, _ := doc["latitude"].(float64)
		rLng, _ := doc["longitude"].(float64)
		dist := h.geo.Distance(lat, lng, rLat, rLng)
		if dist <= radius {
			doc["distance_km"] = dist
			doc["estimated_delivery_min"] = h.geo.EstimateDeliveryTime(dist, 15)
			nearby = append(nearby, doc)
		}
	}

	utils.Success(c, gin.H{
		"restaurants": nearby,
		"total":       len(nearby),
		"center":      gin.H{"lat": lat, "lng": lng},
		"radius_km":   radius,
	})
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

	// Fetch categories
	categories, err := h.appwrite.ListMenuCategories(restaurantID)
	if err != nil {
		// Fall back to flat menu if no categories
		items, itemErr := h.appwrite.ListMenuItems(restaurantID)
		if itemErr != nil {
			utils.InternalError(c, "Failed to fetch menu")
			return
		}
		utils.Success(c, gin.H{"categories": []interface{}{}, "items": items.Documents})
		return
	}

	// Fetch all menu items for this restaurant
	items, err := h.appwrite.ListMenuItems(restaurantID)
	if err != nil {
		utils.InternalError(c, "Failed to fetch menu items")
		return
	}

	// Group items by category_id
	itemsByCategory := make(map[string][]map[string]interface{})
	uncategorized := make([]map[string]interface{}, 0)

	for _, item := range items.Documents {
		catID, _ := item["category_id"].(string)
		if catID != "" {
			itemsByCategory[catID] = append(itemsByCategory[catID], item)
		} else {
			uncategorized = append(uncategorized, item)
		}
	}

	// Build grouped response
	type menuCategory struct {
		ID       string                   `json:"id"`
		Name     string                   `json:"name"`
		SortOrder float64                 `json:"sort_order"`
		Items    []map[string]interface{} `json:"items"`
	}

	groupedMenu := make([]menuCategory, 0)
	for _, cat := range categories.Documents {
		catID, _ := cat["$id"].(string)
		catName, _ := cat["name"].(string)
		sortOrder, _ := cat["sort_order"].(float64)

		groupedMenu = append(groupedMenu, menuCategory{
			ID:        catID,
			Name:      catName,
			SortOrder: sortOrder,
			Items:     itemsByCategory[catID],
		})
	}

	utils.Success(c, gin.H{
		"categories":    groupedMenu,
		"uncategorized": uncategorized,
	})
}

// GetReviews returns paginated reviews for a restaurant
// GET /api/v1/restaurants/:id/reviews
func (h *RestaurantHandler) GetReviews(c *gin.Context) {
	restaurantID := c.Param("id")
	pg := models.ParsePagination(c)

	result, err := h.appwrite.ListReviews(restaurantID)
	if err != nil {
		utils.InternalError(c, "Failed to fetch reviews")
		return
	}
	utils.Paginated(c, result.Documents, pg.Page, pg.PerPage, result.Total)
}
