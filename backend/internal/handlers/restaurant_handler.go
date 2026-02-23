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
	cache    *services.CacheService
}

// NewRestaurantHandler creates a restaurant handler
func NewRestaurantHandler(aw *services.AppwriteService, geo *services.GeoService, cache *services.CacheService) *RestaurantHandler {
	return &RestaurantHandler{appwrite: aw, geo: geo, cache: cache}
}

// List returns restaurants with search/filter/pagination
// @Summary List restaurants
// @Description Returns restaurants with optional search, filter, and pagination
// @Tags Restaurants
// @Produce json
// @Param cuisine query string false "Filter by cuisine type"
// @Param veg_only query string false "Filter vegetarian only (true/false)"
// @Param sort query string false "Sort order (e.g. rating)"
// @Param page query int false "Page number" default(1)
// @Param per_page query int false "Items per page" default(20)
// @Success 200 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/v1/restaurants [get]
func (h *RestaurantHandler) List(c *gin.Context) {
	pg := models.ParsePagination(c)
	queries := []string{
		appwrite.QueryEqual("is_online", true),
		appwrite.QueryLimit(pg.PerPage),
		appwrite.QueryOffset(pg.Offset()),
	}

	if q := c.Query("q"); q != "" {
		queries = append(queries, appwrite.QuerySearch("name", q))
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
// @Summary Find nearby restaurants
// @Description Returns restaurants within a radius using geo bounding box and Haversine distance refinement
// @Tags Restaurants
// @Produce json
// @Param lat query number true "Latitude"
// @Param lng query number true "Longitude"
// @Param radius query number false "Search radius in km (default 5, max 50)"
// @Success 200 {object} map[string]interface{} "restaurants, total, center, radius_km"
// @Failure 400 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/v1/restaurants/nearby [get]
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
// @Summary Get restaurant details
// @Description Returns detailed information about a specific restaurant
// @Tags Restaurants
// @Produce json
// @Param id path string true "Restaurant ID"
// @Success 200 {object} map[string]interface{}
// @Failure 404 {object} map[string]interface{}
// @Router /api/v1/restaurants/{id} [get]
func (h *RestaurantHandler) GetDetail(c *gin.Context) {
	id := c.Param("id")

	// Try cache first
	var cached map[string]interface{}
	if found, _ := h.cache.GetJSON(c.Request.Context(), services.RestaurantDetailKey(id), &cached); found {
		utils.Success(c, cached)
		return
	}

	restaurant, err := h.appwrite.GetRestaurant(id)
	if err != nil {
		utils.NotFound(c, "Restaurant not found")
		return
	}

	_ = h.cache.SetJSON(c.Request.Context(), services.RestaurantDetailKey(id), restaurant, services.RestaurantDetailTTL)
	utils.Success(c, restaurant)
}

// GetMenu returns restaurant menu grouped by categories
// @Summary Get restaurant menu
// @Description Returns the restaurant's menu items grouped by categories
// @Tags Restaurants
// @Produce json
// @Param id path string true "Restaurant ID"
// @Success 200 {object} map[string]interface{} "categories, uncategorized"
// @Failure 500 {object} map[string]interface{}
// @Router /api/v1/restaurants/{id}/menu [get]
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
// @Summary Get restaurant reviews
// @Description Returns paginated reviews for a specific restaurant
// @Tags Restaurants
// @Produce json
// @Param id path string true "Restaurant ID"
// @Param page query int false "Page number" default(1)
// @Param per_page query int false "Items per page" default(20)
// @Success 200 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/v1/restaurants/{id}/reviews [get]
func (h *RestaurantHandler) GetReviews(c *gin.Context) {
	restaurantID := c.Param("id")
	pg := models.ParsePagination(c)

	result, err := h.appwrite.ListReviewsByQuery([]string{
		appwrite.QueryEqual("restaurant_id", restaurantID),
		appwrite.QueryOrderDesc("created_at"),
		appwrite.QueryLimit(pg.PerPage),
		appwrite.QueryOffset(pg.Offset()),
	})
	if err != nil {
		utils.InternalError(c, "Failed to fetch reviews")
		return
	}
	utils.Paginated(c, result.Documents, pg.Page, pg.PerPage, result.Total)
}
