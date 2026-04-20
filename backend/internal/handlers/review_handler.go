package handlers

import (
	"log"
	"strings"
	"time"

	"github.com/chizze/backend/internal/middleware"
	"github.com/chizze/backend/internal/models"
	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/internal/websocket"
	"github.com/chizze/backend/pkg/appwrite"
	"github.com/chizze/backend/pkg/utils"
	"github.com/gin-gonic/gin"
)

// ReviewHandler handles review endpoints
type ReviewHandler struct {
	appwrite    *services.AppwriteService
	broadcaster *websocket.EventBroadcaster
}

// NewReviewHandler creates a review handler
func NewReviewHandler(aw *services.AppwriteService, broadcaster *websocket.EventBroadcaster) *ReviewHandler {
	return &ReviewHandler{appwrite: aw, broadcaster: broadcaster}
}

// CreateReview submits a review for an order with ownership/duplicate/status checks
// @Summary      Create a review
// @Description  Submits a review for a delivered order. Validates ownership, delivery status, and duplicate checks.
// @Tags         Reviews
// @Accept       json
// @Produce      json
// @Param        id    path      string                      true  "Order ID"
// @Param        body  body      models.CreateReviewRequest  true  "Review data"
// @Success      201  {object}  map[string]interface{}
// @Failure      400  {object}  map[string]interface{}
// @Failure      403  {object}  map[string]interface{}
// @Failure      404  {object}  map[string]interface{}
// @Failure      500  {object}  map[string]interface{}
// @Security     BearerAuth
// @Router       /api/v1/orders/{id}/review [post]
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
	normalizedStatus := strings.ToLower(strings.TrimSpace(status))
	if normalizedStatus != strings.ToLower(models.OrderStatusDelivered) && normalizedStatus != "completed" {
		utils.BadRequest(c, "You can only review delivered orders")
		return
	}

	// Duplicate review check.
	//
	// We use a deterministic document ID (`rev_<orderID>`) so the primary
	// duplicate check is a cheap point lookup that works without any index
	// on the reviews collection. The previous filter-query approach failed
	// with 500 "Failed to validate existing reviews" whenever the Appwrite
	// `reviews` collection lacked an index on `order_id`+`customer_id` —
	// which blocked every customer from submitting a rating.
	//
	// A legacy filter check runs as a secondary line of defence to catch
	// reviews that were created with Appwrite's `unique()` IDs before this
	// handler switched to deterministic keys. That check is fail-open: if
	// the query errors (e.g. missing index), we log and continue rather
	// than blocking the customer.
	reviewID := "rev_" + orderID
	if existing, getErr := h.appwrite.GetReview(reviewID); getErr == nil && existing != nil {
		utils.BadRequest(c, "You have already reviewed this order")
		return
	} else if getErr != nil && !appwrite.IsNotFound(getErr) {
		log.Printf("[ReviewHandler.CreateReview] deterministic dup lookup for order %s failed (continuing): %v", orderID, getErr)
	}

	if legacy, err := h.appwrite.ListReviewsByQuery([]string{
		appwrite.QueryEqual("order_id", orderID),
		appwrite.QueryEqual("customer_id", userID),
		appwrite.QueryLimit(1),
	}); err != nil {
		// Fail-open: index/schema issues on the reviews collection must not
		// block submission — the deterministic ID above and the 409 handling
		// on Create below still prevent duplicates.
		log.Printf("[ReviewHandler.CreateReview] legacy dup filter failed for order %s (non-fatal): %v", orderID, err)
	} else if legacy.Total > 0 {
		utils.BadRequest(c, "You have already reviewed this order")
		return
	}

	restaurantID, _ := order["restaurant_id"].(string)
	deliveryPartnerID, _ := order["delivery_partner_id"].(string)
	deliveryRating := req.FoodRating
	if req.DeliveryRating != nil {
		deliveryRating = *req.DeliveryRating
	}

	// `tags` must be a non-nil slice; Appwrite string-array attributes reject
	// JSON `null` with 400 document_invalid_structure, and the client sometimes
	// sends a missing/null field when the user didn't tap any tag chip.
	tags := req.Tags
	if tags == nil {
		tags = []string{}
	}

	reviewData := map[string]interface{}{
		"order_id":        orderID,
		"customer_id":     userID,
		"restaurant_id":   restaurantID,
		"food_rating":     req.FoodRating,
		"delivery_rating": deliveryRating,
		"review_text":     req.ReviewText,
		"tags":            tags,
		"is_visible":      true,
		"created_at":      time.Now().Format(time.RFC3339),
	}
	// Only include delivery_partner_id when we actually have a rider. Pickup
	// orders, orders cancelled before assignment, and legacy records without
	// the denormalized field leave this empty — and the production Appwrite
	// attribute is relationship/min-length constrained, so writing "" fails
	// with 400 document_invalid_structure and blocks every such review.
	if deliveryPartnerID != "" {
		reviewData["delivery_partner_id"] = deliveryPartnerID
	}

	doc, err := h.appwrite.CreateReview(reviewID, reviewData)
	if err != nil {
		// 409 from Appwrite means the deterministic ID already exists —
		// i.e. someone submitted between our GetReview lookup and this
		// Create. Treat as a duplicate rather than a server error so the
		// client gets an accurate, user-friendly message.
		if appwrite.IsConflict(err) {
			utils.BadRequest(c, "You have already reviewed this order")
			return
		}
		log.Printf("[ReviewHandler.CreateReview] Failed to create review for order %s: %v", orderID, err)
		utils.InternalError(c, "Failed to submit review")
		return
	}

	// Update restaurant average rating asynchronously (best-effort)
	go h.updateRestaurantRating(restaurantID)

	// Notify the restaurant owner so the partner dashboard surfaces new reviews
	// without polling. Fire-and-forget; failure here must not fail the request.
	go h.notifyRestaurantOwner(restaurantID, orderID, req.FoodRating)

	utils.Created(c, doc)
}

// notifyRestaurantOwner sends an in-app notification + WS broadcast to the
// owner of `restaurantID` informing them of a new review on the given order.
func (h *ReviewHandler) notifyRestaurantOwner(restaurantID, orderID string, rating int) {
	if restaurantID == "" {
		return
	}
	restaurant, err := h.appwrite.GetRestaurant(restaurantID)
	if err != nil || restaurant == nil {
		return
	}
	ownerID, _ := restaurant["owner_id"].(string)
	if ownerID == "" {
		return
	}
	title := "New review"
	body := "A customer just rated your restaurant"
	if rating > 0 {
		body = "A customer rated their order " + strings.Repeat("⭐", rating)
	}
	_, _ = h.appwrite.CreateNotification("unique()", map[string]interface{}{
		"user_id": ownerID,
		"title":   title,
		"body":    body,
		"type":    "review",
		"data": map[string]interface{}{
			"order_id":      orderID,
			"restaurant_id": restaurantID,
			"deep_link":     "/partner/reviews",
		},
		"is_read": false,
	})
	if h.broadcaster != nil {
		h.broadcaster.BroadcastNotification(ownerID, title, body, "review")
	}
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
		if isVisible, ok := rev["is_visible"].(bool); ok && !isVisible {
			continue
		}
		foodRating, _ := rev["food_rating"].(float64)
		if foodRating > 0 {
			totalRating += foodRating
			count++
		}
	}

	if count > 0 {
		avgRating := totalRating / float64(count)
		_, _ = h.appwrite.UpdateRestaurant(restaurantID, map[string]interface{}{
			"rating":        avgRating,
			"total_ratings": count,
		})
	}
}

// ReplyToReview lets restaurant owner reply to a review with ownership check
// @Summary      Reply to a review
// @Description  Allows a restaurant owner to reply to a review with ownership verification
// @Tags         Reviews
// @Accept       json
// @Produce      json
// @Param        id    path      string                     true  "Review ID"
// @Param        body  body      models.ReplyReviewRequest  true  "Reply text"
// @Success      200  {object}  map[string]interface{}
// @Failure      400  {object}  map[string]interface{}
// @Failure      403  {object}  map[string]interface{}
// @Failure      404  {object}  map[string]interface{}
// @Failure      500  {object}  map[string]interface{}
// @Security     BearerAuth
// @Router       /api/v1/partner/reviews/{id}/reply [post]
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
