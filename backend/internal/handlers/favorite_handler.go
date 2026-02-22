package handlers

import (
	"time"

	"github.com/chizze/backend/internal/models"
	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/pkg/utils"
	"github.com/gin-gonic/gin"
)

// FavoriteHandler handles user favorites endpoints
type FavoriteHandler struct {
	appwrite *services.AppwriteService
}

// NewFavoriteHandler creates a favorite handler
func NewFavoriteHandler(aw *services.AppwriteService) *FavoriteHandler {
	return &FavoriteHandler{appwrite: aw}
}

// List returns the user's favorite restaurants
// @Summary      List favorite restaurants
// @Description  Returns the authenticated user's favorite restaurants with restaurant details
// @Tags         Favorites
// @Accept       json
// @Produce      json
// @Success      200  {array}   map[string]interface{}
// @Failure      500  {object}  map[string]interface{}
// @Security     BearerAuth
// @Router       /api/v1/users/me/favorites [get]
func (h *FavoriteHandler) List(c *gin.Context) {
	userID := c.GetString("user_id")

	result, err := h.appwrite.ListFavorites(userID)
	if err != nil {
		utils.InternalError(c, "Failed to fetch favorites")
		return
	}

	// Enrich with restaurant data
	favorites := make([]gin.H, 0, len(result.Documents))
	for _, doc := range result.Documents {
		restaurantID, _ := doc["restaurant_id"].(string)
		fav := gin.H{
			"$id":           doc["$id"],
			"restaurant_id": restaurantID,
			"created_at":    doc["created_at"],
		}
		// Try to fetch restaurant details
		if restaurantID != "" {
			restaurant, err := h.appwrite.GetRestaurant(restaurantID)
			if err == nil {
				fav["restaurant"] = restaurant
			}
		}
		favorites = append(favorites, fav)
	}

	utils.Success(c, favorites)
}

// Add adds a restaurant to the user's favorites
// @Summary      Add a favorite restaurant
// @Description  Adds a restaurant to the authenticated user's favorites
// @Tags         Favorites
// @Accept       json
// @Produce      json
// @Param        body  body      models.CreateFavoriteRequest  true  "Favorite data"
// @Success      201  {object}  map[string]interface{}
// @Failure      400  {object}  map[string]interface{}
// @Failure      404  {object}  map[string]interface{}
// @Failure      500  {object}  map[string]interface{}
// @Security     BearerAuth
// @Router       /api/v1/users/me/favorites [post]
func (h *FavoriteHandler) Add(c *gin.Context) {
	userID := c.GetString("user_id")

	var req models.CreateFavoriteRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Restaurant ID is required")
		return
	}

	// Check if already favorited
	existing, err := h.appwrite.FindFavorite(userID, req.RestaurantID)
	if err == nil && existing.Total > 0 {
		utils.BadRequest(c, "Restaurant already in favorites")
		return
	}

	// Verify restaurant exists
	_, err = h.appwrite.GetRestaurant(req.RestaurantID)
	if err != nil {
		utils.NotFound(c, "Restaurant not found")
		return
	}

	data := map[string]interface{}{
		"user_id":       userID,
		"restaurant_id": req.RestaurantID,
		"created_at":    time.Now().Format(time.RFC3339),
	}

	doc, err := h.appwrite.CreateFavorite("unique()", data)
	if err != nil {
		utils.InternalError(c, "Failed to add favorite")
		return
	}

	utils.Created(c, doc)
}

// Remove removes a restaurant from the user's favorites
// @Summary      Remove a favorite restaurant
// @Description  Removes a restaurant from the authenticated user's favorites
// @Tags         Favorites
// @Accept       json
// @Produce      json
// @Param        restaurant_id  path      string  true  "Restaurant ID"
// @Success      200  {object}  map[string]interface{}
// @Failure      404  {object}  map[string]interface{}
// @Failure      500  {object}  map[string]interface{}
// @Security     BearerAuth
// @Router       /api/v1/users/me/favorites/{restaurant_id} [delete]
func (h *FavoriteHandler) Remove(c *gin.Context) {
	userID := c.GetString("user_id")
	restaurantID := c.Param("restaurant_id")

	// Find the favorite document
	result, err := h.appwrite.FindFavorite(userID, restaurantID)
	if err != nil || result.Total == 0 {
		utils.NotFound(c, "Favorite not found")
		return
	}

	docID, _ := result.Documents[0]["$id"].(string)
	if err := h.appwrite.DeleteFavorite(docID); err != nil {
		utils.InternalError(c, "Failed to remove favorite")
		return
	}

	utils.Success(c, gin.H{"message": "Removed from favorites"})
}
