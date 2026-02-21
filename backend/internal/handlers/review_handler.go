package handlers

import (
	"time"

	"github.com/chizze/backend/internal/middleware"
	"github.com/chizze/backend/internal/models"
	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/pkg/appwrite"
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

// CreateReview submits a review for an order with ownership/duplicate/status checks
// POST /api/v1/orders/:id/review
func (h *ReviewHandler) CreateReview(c *gin.Context) {
	orderID := c.Param("id")
	userID := middleware.GetUserID(c)

	var req models.CreateReviewRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Invalid review data")
		return
	}

	// Get order
	order, err := h.appwrite.GetOrder(orderID)
	if err != nil {
		utils.NotFound(c, "Order not found")
		return
	}

	// Ownership check
	custID, _ := order["customer_id"].(string)
	if custID != userID {
		utils.Forbidden(c, "You can only review your own orders")
		return
	}

	// Order must be delivered
	status, _ := order["status"].(string)
	if status != models.OrderStatusDelivered {
		utils.BadRequest(c, "You can only review delivered orders")
		return
	}

	// Duplicate review check
	existing, err := h.appwrite.ListReviewsByQuery([]string{
		appwrite.QueryEqual("order_id", orderID),
		appwrite.QueryEqual("customer_id", userID),
		appwrite.QueryLimit(1),
	})
	if err == nil && existing.Total > 0 {
		utils.BadRequest(c, "You have already reviewed this order")
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

	// Update restaurant average rating asynchronously (best-effort)
	go h.updateRestaurantRating(restaurantID)

	utils.Created(c, doc)
}

// updateRestaurantRating recalculates restaurant average from all reviews
func (h *ReviewHandler) updateRestaurantRating(restaurantID string) {
	reviews, err := h.appwrite.ListReviews(restaurantID)
	if err != nil || reviews.Total == 0 {
		return
	}

	var totalRating float64
	count := 0
	for _, rev := range reviews.Documents {
		foodRating, _ := rev["food_rating"].(float64)
		if foodRating > 0 {
			totalRating += foodRating
			count++
		}
	}

	if count > 0 {
		avgRating := totalRating / float64(count)
		_, _ = h.appwrite.UpdateRestaurant(restaurantID, map[string]interface{}{
			"rating":       avgRating,
			"total_reviews": count,
		})
	}
}

// ReplyToReview lets restaurant owner reply to a review with ownership check
// POST /api/v1/partner/reviews/:id/reply
func (h *ReviewHandler) ReplyToReview(c *gin.Context) {
	userID := middleware.GetUserID(c)
	reviewID := c.Param("id")

	var req models.ReplyReviewRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Reply text is required")
		return
	}

	// Get review and verify ownership through restaurant
	review, err := h.appwrite.GetReview(reviewID)
	if err != nil {
		utils.NotFound(c, "Review not found")
		return
	}

	reviewRestID, _ := review["restaurant_id"].(string)
	result, err := h.appwrite.GetRestaurantByOwner(userID)
	if err != nil || result == nil || len(result.Documents) == 0 {
		utils.Forbidden(c, "Not a restaurant owner")
		return
	}
	myRestID, _ := result.Documents[0]["$id"].(string)
	if reviewRestID != myRestID {
		utils.Forbidden(c, "This review is not for your restaurant")
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
