package handlers

import (
	"time"

	"github.com/chizze/backend/internal/middleware"
	"github.com/chizze/backend/internal/models"
	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/pkg/utils"
	"github.com/gin-gonic/gin"
)

// ReviewHandler handles review endpoints
type ReviewHandler struct {
	appwrite *services.AppwriteService
}

// NewReviewHandler creates a review handler
func NewReviewHandler(aw *services.AppwriteService) *ReviewHandler {
	return &ReviewHandler{appwrite: aw}
}

// CreateReview submits a review for an order
// POST /api/v1/orders/:id/review
func (h *ReviewHandler) CreateReview(c *gin.Context) {
	orderID := c.Param("id")
	userID := middleware.GetUserID(c)

	var req models.CreateReviewRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Invalid review data")
		return
	}

	// Get order to extract restaurant_id
	order, err := h.appwrite.GetOrder(orderID)
	if err != nil {
		utils.NotFound(c, "Order not found")
		return
	}

	restaurantID, _ := order["restaurant_id"].(string)
	deliveryPartnerID, _ := order["delivery_partner_id"].(string)

	reviewData := map[string]interface{}{
		"order_id":            orderID,
		"customer_id":         userID,
		"restaurant_id":       restaurantID,
		"delivery_partner_id": deliveryPartnerID,
		"food_rating":         req.FoodRating,
		"delivery_rating":     req.DeliveryRating,
		"review_text":         req.ReviewText,
		"tags":                req.Tags,
		"is_visible":          true,
		"created_at":          time.Now().Format(time.RFC3339),
	}

	doc, err := h.appwrite.CreateReview("unique()", reviewData)
	if err != nil {
		utils.InternalError(c, "Failed to submit review")
		return
	}
	utils.Created(c, doc)
}

// ReplyToReview lets restaurant reply to a review
// POST /api/v1/partner/reviews/:id/reply
func (h *ReviewHandler) ReplyToReview(c *gin.Context) {
	reviewID := c.Param("id")

	var req models.ReplyReviewRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Reply text is required")
		return
	}

	updated, err := h.appwrite.UpdateReview(reviewID, map[string]interface{}{
		"restaurant_reply": req.Reply,
	})
	if err != nil {
		utils.InternalError(c, "Failed to submit reply")
		return
	}
	utils.Success(c, updated)
}
