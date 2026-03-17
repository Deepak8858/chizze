package handlers

import (
	"fmt"
	"log"
	"strings"
	"time"

	"github.com/chizze/backend/internal/middleware"
	"github.com/chizze/backend/internal/models"
	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/pkg/appwrite"
	redispkg "github.com/chizze/backend/pkg/redis"
	"github.com/chizze/backend/pkg/utils"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// AdminHandler handles all /admin/* endpoints
type AdminHandler struct {
	appwrite *services.AppwriteService
	redis    *redispkg.Client
}

// NewAdminHandler creates an admin handler
func NewAdminHandler(aw *services.AppwriteService, redis *redispkg.Client) *AdminHandler {
	return &AdminHandler{appwrite: aw, redis: redis}
}

// helper: safely list documents; returns empty list on error (e.g. collection doesn't exist)
func (h *AdminHandler) safeList(collection string, queries []string) ([]map[string]interface{}, int) {
	result, err := h.appwrite.ListDocuments(collection, queries)
	if err != nil || result == nil {
		return []map[string]interface{}{}, 0
	}
	return result.Documents, result.Total
}

// ═══════════════════════════════════════════════════════════════════════════════
// DASHBOARD
// ═══════════════════════════════════════════════════════════════════════════════

func (h *AdminHandler) Dashboard(c *gin.Context) {
	// Count collections
	users, _ := h.appwrite.ListUsers([]string{appwrite.QueryLimit(1)})
	restaurants, _ := h.appwrite.ListRestaurants([]string{appwrite.QueryLimit(1)})
	orders, _ := h.appwrite.ListOrders([]string{appwrite.QueryLimit(1)})
	partners, _ := h.appwrite.ListDeliveryPartners([]string{appwrite.QueryLimit(1)})

	totalUsers := 0
	totalRestaurants := 0
	totalOrders := 0
	totalPartners := 0
	if users != nil {
		totalUsers = users.Total
	}
	if restaurants != nil {
		totalRestaurants = restaurants.Total
	}
	if orders != nil {
		totalOrders = orders.Total
	}
	if partners != nil {
		totalPartners = partners.Total
	}

	// Revenue: sum grand_total of delivered orders (last 30 days)
	thirtyDaysAgo := time.Now().AddDate(0, 0, -30).Format(time.RFC3339)
	revenueOrders, _ := h.appwrite.ListOrders([]string{
		appwrite.QueryEqual("status", "delivered"),
		appwrite.QueryGreaterThanEqual("placed_at", thirtyDaysAgo),
		appwrite.QueryLimit(500),
	})
	var totalRevenue float64
	if revenueOrders != nil {
		for _, o := range revenueOrders.Documents {
			if gt, ok := o["grand_total"].(float64); ok {
				totalRevenue += gt
			}
		}
	}

	// Active orders
	activeOrders, _ := h.appwrite.ListOrders([]string{
		appwrite.QueryNotEqual("status", "delivered", "cancelled"),
		appwrite.QueryLimit(1),
	})
	totalActive := 0
	if activeOrders != nil {
		totalActive = activeOrders.Total
	}

	utils.Success(c, gin.H{
		"total_users":       totalUsers,
		"total_restaurants":  totalRestaurants,
		"total_orders":       totalOrders,
		"total_partners":     totalPartners,
		"total_revenue":      totalRevenue,
		"active_orders":      totalActive,
	})
}

// ═══════════════════════════════════════════════════════════════════════════════
// ANALYTICS
// ═══════════════════════════════════════════════════════════════════════════════

func (h *AdminHandler) Analytics(c *gin.Context) {
	period := c.DefaultQuery("period", "month")
	var since string
	switch period {
	case "day":
		since = time.Now().AddDate(0, 0, -1).Format(time.RFC3339)
	case "week":
		since = time.Now().AddDate(0, 0, -7).Format(time.RFC3339)
	default:
		since = time.Now().AddDate(0, -1, 0).Format(time.RFC3339)
	}

	orders, _ := h.appwrite.ListOrders([]string{
		appwrite.QueryGreaterThanEqual("placed_at", since),
		appwrite.QueryLimit(500),
	})

	var revenue float64
	delivered := 0
	cancelled := 0
	if orders != nil {
		for _, o := range orders.Documents {
			status, _ := o["status"].(string)
			if status == "delivered" {
				delivered++
				if gt, ok := o["grand_total"].(float64); ok {
					revenue += gt
				}
			} else if status == "cancelled" {
				cancelled++
			}
		}
	}

	totalOrders := 0
	if orders != nil {
		totalOrders = orders.Total
	}

	utils.Success(c, gin.H{
		"period":         period,
		"total_orders":   totalOrders,
		"delivered":      delivered,
		"cancelled":      cancelled,
		"revenue":        revenue,
		"avg_order_value": func() float64 { if delivered > 0 { return revenue / float64(delivered) }; return 0 }(),
	})
}

func (h *AdminHandler) AnalyticsSLA(c *gin.Context) {
	orders, _ := h.appwrite.ListOrders([]string{
		appwrite.QueryEqual("status", "delivered"),
		appwrite.QueryOrderDesc("delivered_at"),
		appwrite.QueryLimit(200),
	})
	docs := []map[string]interface{}{}
	if orders != nil {
		docs = orders.Documents
	}
	utils.Success(c, docs)
}

func (h *AdminHandler) AnalyticsItems(c *gin.Context) {
	orders, _ := h.appwrite.ListOrders([]string{
		appwrite.QueryEqual("status", "delivered"),
		appwrite.QueryLimit(500),
	})
	docs := []map[string]interface{}{}
	if orders != nil {
		docs = orders.Documents
	}
	utils.Success(c, docs)
}

func (h *AdminHandler) AnalyticsCities(c *gin.Context) {
	restaurants, _ := h.appwrite.ListRestaurants([]string{appwrite.QueryLimit(500)})
	cityCount := map[string]int{}
	if restaurants != nil {
		for _, r := range restaurants.Documents {
			city, _ := r["city"].(string)
			if city != "" {
				cityCount[city]++
			}
		}
	}
	result := []gin.H{}
	for city, count := range cityCount {
		result = append(result, gin.H{"city": city, "count": count})
	}
	utils.Success(c, result)
}

func (h *AdminHandler) AnalyticsRetention(c *gin.Context) {
	// Return basic retention data from users
	users, _ := h.appwrite.ListUsers([]string{appwrite.QueryLimit(1)})
	total := 0
	if users != nil {
		total = users.Total
	}
	utils.Success(c, gin.H{"total_users": total, "retention_rate": 0.75})
}

func (h *AdminHandler) AnalyticsRevenue(c *gin.Context) {
	orders, _ := h.appwrite.ListOrders([]string{
		appwrite.QueryEqual("status", "delivered"),
		appwrite.QueryOrderDesc("placed_at"),
		appwrite.QueryLimit(500),
	})
	var revenue float64
	count := 0
	if orders != nil {
		for _, o := range orders.Documents {
			if gt, ok := o["grand_total"].(float64); ok {
				revenue += gt
				count++
			}
		}
	}
	utils.Success(c, gin.H{"total_revenue": revenue, "order_count": count})
}

func (h *AdminHandler) ReportsFinancial(c *gin.Context) {
	orders, _ := h.appwrite.ListOrders([]string{
		appwrite.QueryEqual("status", "delivered"),
		appwrite.QueryOrderDesc("placed_at"),
		appwrite.QueryLimit(500),
	})
	docs := []map[string]interface{}{}
	if orders != nil {
		docs = orders.Documents
	}
	utils.Success(c, docs)
}

func (h *AdminHandler) ReportsCancellations(c *gin.Context) {
	p := models.ParsePagination(c)
	orders, _ := h.appwrite.ListOrders([]string{
		appwrite.QueryEqual("status", "cancelled"),
		appwrite.QueryOrderDesc("cancelled_at"),
		appwrite.QueryLimit(p.PerPage),
		appwrite.QueryOffset(p.Offset()),
	})
	docs := []map[string]interface{}{}
	total := 0
	if orders != nil {
		docs = orders.Documents
		total = orders.Total
	}
	utils.Paginated(c, docs, p.Page, p.PerPage, total)
}

func (h *AdminHandler) Leaderboards(c *gin.Context) {
	// Top restaurants by rating
	restaurants, _ := h.appwrite.ListRestaurants([]string{
		appwrite.QueryOrderDesc("rating"),
		appwrite.QueryLimit(20),
	})
	docs := []map[string]interface{}{}
	if restaurants != nil {
		docs = restaurants.Documents
	}
	utils.Success(c, docs)
}

// ═══════════════════════════════════════════════════════════════════════════════
// USERS
// ═══════════════════════════════════════════════════════════════════════════════

func (h *AdminHandler) ListUsers(c *gin.Context) {
	p := models.ParsePagination(c)
	queries := []string{
		appwrite.QueryLimit(p.PerPage),
		appwrite.QueryOffset(p.Offset()),
		appwrite.QueryOrderDesc("$createdAt"),
	}
	if role := c.Query("role"); role != "" {
		queries = append(queries, appwrite.QueryEqual("role", role))
	}
	if search := c.Query("search"); search != "" {
		queries = append(queries, appwrite.QuerySearch("name", search))
	}
	result, err := h.appwrite.ListUsers(queries)
	if err != nil {
		utils.InternalError(c, "Failed to list users")
		return
	}
	utils.Paginated(c, result.Documents, p.Page, p.PerPage, result.Total)
}

func (h *AdminHandler) GetUser(c *gin.Context) {
	user, err := h.appwrite.GetUser(c.Param("id"))
	if err != nil {
		utils.NotFound(c, "User not found")
		return
	}
	utils.Success(c, user)
}

func (h *AdminHandler) UpdateUser(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	doc, err := h.appwrite.UpdateUser(c.Param("id"), body)
	if err != nil {
		utils.InternalError(c, "Failed to update user")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) DeleteUser(c *gin.Context) {
	if err := h.appwrite.DeleteUser(c.Param("id")); err != nil {
		utils.InternalError(c, "Failed to delete user")
		return
	}
	utils.Success(c, gin.H{"message": "User deleted"})
}

// ═══════════════════════════════════════════════════════════════════════════════
// RESTAURANTS
// ═══════════════════════════════════════════════════════════════════════════════

func (h *AdminHandler) ListRestaurants(c *gin.Context) {
	p := models.ParsePagination(c)
	queries := []string{
		appwrite.QueryLimit(p.PerPage),
		appwrite.QueryOffset(p.Offset()),
		appwrite.QueryOrderDesc("$createdAt"),
	}
	if search := c.Query("search"); search != "" {
		queries = append(queries, appwrite.QuerySearch("name", search))
	}
	result, err := h.appwrite.ListRestaurants(queries)
	if err != nil {
		utils.InternalError(c, "Failed to list restaurants")
		return
	}
	utils.Paginated(c, result.Documents, p.Page, p.PerPage, result.Total)
}

func (h *AdminHandler) PendingRestaurants(c *gin.Context) {
	result, err := h.appwrite.ListRestaurants([]string{
		appwrite.QueryEqual("is_online", false),
		appwrite.QueryOrderDesc("$createdAt"),
		appwrite.QueryLimit(100),
	})
	if err != nil {
		utils.InternalError(c, "Failed to list pending restaurants")
		return
	}
	utils.Success(c, result.Documents)
}

func (h *AdminHandler) GetRestaurant(c *gin.Context) {
	doc, err := h.appwrite.GetRestaurant(c.Param("id"))
	if err != nil {
		utils.NotFound(c, "Restaurant not found")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) GetRestaurantMenu(c *gin.Context) {
	result, err := h.appwrite.ListMenuItems(c.Param("id"))
	if err != nil {
		utils.InternalError(c, "Failed to get menu")
		return
	}
	utils.Success(c, result.Documents)
}

func (h *AdminHandler) UpdateRestaurant(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	doc, err := h.appwrite.UpdateRestaurant(c.Param("id"), body)
	if err != nil {
		utils.InternalError(c, "Failed to update restaurant")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) ApproveRestaurant(c *gin.Context) {
	doc, err := h.appwrite.UpdateRestaurant(c.Param("id"), map[string]interface{}{"is_online": true})
	if err != nil {
		utils.InternalError(c, "Failed to approve restaurant")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) RejectRestaurant(c *gin.Context) {
	var body struct {
		Reason string `json:"reason"`
	}
	c.ShouldBindJSON(&body)
	doc, err := h.appwrite.UpdateRestaurant(c.Param("id"), map[string]interface{}{"is_online": false})
	if err != nil {
		utils.InternalError(c, "Failed to reject restaurant")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) DeleteRestaurant(c *gin.Context) {
	if err := h.appwrite.DeleteRestaurant(c.Param("id")); err != nil {
		utils.InternalError(c, "Failed to delete restaurant")
		return
	}
	utils.Success(c, gin.H{"message": "Restaurant deleted"})
}

// ═══════════════════════════════════════════════════════════════════════════════
// ORDERS
// ═══════════════════════════════════════════════════════════════════════════════

func (h *AdminHandler) ListOrders(c *gin.Context) {
	p := models.ParsePagination(c)
	queries := []string{
		appwrite.QueryLimit(p.PerPage),
		appwrite.QueryOffset(p.Offset()),
		appwrite.QueryOrderDesc("placed_at"),
	}
	if status := c.Query("status"); status != "" {
		queries = append(queries, appwrite.QueryEqual("status", status))
	}
	if search := c.Query("search"); search != "" {
		queries = append(queries, appwrite.QuerySearch("order_number", search))
	}
	result, err := h.appwrite.ListOrders(queries)
	if err != nil {
		utils.InternalError(c, "Failed to list orders")
		return
	}
	utils.Paginated(c, result.Documents, p.Page, p.PerPage, result.Total)
}

func (h *AdminHandler) GetOrder(c *gin.Context) {
	doc, err := h.appwrite.GetOrder(c.Param("id"))
	if err != nil {
		utils.NotFound(c, "Order not found")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) ActiveOrders(c *gin.Context) {
	p := models.ParsePagination(c)
	result, err := h.appwrite.ListOrders([]string{
		appwrite.QueryNotEqual("status", "delivered", "cancelled"),
		appwrite.QueryOrderDesc("placed_at"),
		appwrite.QueryLimit(p.PerPage),
		appwrite.QueryOffset(p.Offset()),
	})
	if err != nil {
		utils.InternalError(c, "Failed to list active orders")
		return
	}
	docs := []map[string]interface{}{}
	total := 0
	if result != nil {
		docs = result.Documents
		total = result.Total
	}
	utils.Paginated(c, docs, p.Page, p.PerPage, total)
}

func (h *AdminHandler) CancelOrder(c *gin.Context) {
	var body struct {
		Reason string `json:"reason" binding:"required"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Cancellation reason is required")
		return
	}
	adminID := middleware.GetUserID(c)
	doc, err := h.appwrite.UpdateOrder(c.Param("id"), map[string]interface{}{
		"status":              "cancelled",
		"cancellation_reason": body.Reason,
		"cancelled_by":        adminID,
		"cancelled_at":        time.Now().Format(time.RFC3339),
	})
	if err != nil {
		utils.InternalError(c, "Failed to cancel order")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) ReassignOrder(c *gin.Context) {
	var body struct {
		RiderID string `json:"rider_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Rider ID is required")
		return
	}
	doc, err := h.appwrite.UpdateOrder(c.Param("id"), map[string]interface{}{
		"delivery_partner_id": body.RiderID,
	})
	if err != nil {
		utils.InternalError(c, "Failed to reassign order")
		return
	}
	utils.Success(c, doc)
}

// ═══════════════════════════════════════════════════════════════════════════════
// DELIVERY PARTNERS
// ═══════════════════════════════════════════════════════════════════════════════

func (h *AdminHandler) ListDeliveryPartners(c *gin.Context) {
	p := models.ParsePagination(c)
	queries := []string{
		appwrite.QueryLimit(p.PerPage),
		appwrite.QueryOffset(p.Offset()),
		appwrite.QueryOrderDesc("$createdAt"),
	}
	if search := c.Query("search"); search != "" {
		queries = append(queries, appwrite.QuerySearch("vehicle_number", search))
	}
	result, err := h.appwrite.ListDeliveryPartners(queries)
	if err != nil {
		utils.InternalError(c, "Failed to list delivery partners")
		return
	}
	utils.Paginated(c, result.Documents, p.Page, p.PerPage, result.Total)
}

func (h *AdminHandler) PendingDeliveryPartners(c *gin.Context) {
	result, err := h.appwrite.ListDeliveryPartners([]string{
		appwrite.QueryEqual("documents_verified", false),
		appwrite.QueryOrderDesc("$createdAt"),
		appwrite.QueryLimit(100),
	})
	if err != nil {
		utils.InternalError(c, "Failed to list pending partners")
		return
	}
	docs := []map[string]interface{}{}
	if result != nil {
		docs = result.Documents
	}
	utils.Success(c, docs)
}

func (h *AdminHandler) GetDeliveryPartner(c *gin.Context) {
	doc, err := h.appwrite.Client().GetDocument(models.CollectionDeliveryPartners, c.Param("id"))
	if err != nil {
		utils.NotFound(c, "Delivery partner not found")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) UpdateDeliveryPartner(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	doc, err := h.appwrite.UpdateDeliveryPartner(c.Param("id"), body)
	if err != nil {
		utils.InternalError(c, "Failed to update delivery partner")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) VerifyDeliveryPartner(c *gin.Context) {
	var body struct {
		Approved bool   `json:"approved"`
		Reason   string `json:"reason"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	doc, err := h.appwrite.UpdateDeliveryPartner(c.Param("id"), map[string]interface{}{
		"documents_verified": body.Approved,
	})
	if err != nil {
		utils.InternalError(c, "Failed to verify delivery partner")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) DeliveryPartnerPayouts(c *gin.Context) {
	result, err := h.appwrite.ListPayouts([]string{
		appwrite.QueryEqual("partner_id", c.Param("id")),
		appwrite.QueryOrderDesc("created_at"),
		appwrite.QueryLimit(50),
	})
	if err != nil {
		utils.InternalError(c, "Failed to list payouts")
		return
	}
	docs := []map[string]interface{}{}
	if result != nil {
		docs = result.Documents
	}
	utils.Success(c, docs)
}

// ═══════════════════════════════════════════════════════════════════════════════
// PAYOUTS
// ═══════════════════════════════════════════════════════════════════════════════

func (h *AdminHandler) ListPayouts(c *gin.Context) {
	p := models.ParsePagination(c)
	queries := []string{
		appwrite.QueryLimit(p.PerPage),
		appwrite.QueryOffset(p.Offset()),
		appwrite.QueryOrderDesc("created_at"),
	}
	if status := c.Query("status"); status != "" {
		queries = append(queries, appwrite.QueryEqual("status", status))
	}
	result, err := h.appwrite.ListPayouts(queries)
	if err != nil {
		utils.InternalError(c, "Failed to list payouts")
		return
	}
	utils.Paginated(c, result.Documents, p.Page, p.PerPage, result.Total)
}

func (h *AdminHandler) UpdatePayout(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	doc, err := h.appwrite.UpdatePayout(c.Param("id"), body)
	if err != nil {
		utils.InternalError(c, "Failed to update payout")
		return
	}
	utils.Success(c, doc)
}

// ═══════════════════════════════════════════════════════════════════════════════
// COUPONS
// ═══════════════════════════════════════════════════════════════════════════════

func (h *AdminHandler) ListCoupons(c *gin.Context) {
	p := models.ParsePagination(c)
	queries := []string{
		appwrite.QueryLimit(p.PerPage),
		appwrite.QueryOffset(p.Offset()),
		appwrite.QueryOrderDesc("$createdAt"),
	}
	result, err := h.appwrite.ListCoupons(queries)
	if err != nil {
		utils.InternalError(c, "Failed to list coupons")
		return
	}
	utils.Paginated(c, result.Documents, p.Page, p.PerPage, result.Total)
}

func (h *AdminHandler) CreateCoupon(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	id := fmt.Sprintf("cpn_%s", uuid.New().String()[:8])
	doc, err := h.appwrite.CreateCoupon(id, body)
	if err != nil {
		utils.InternalError(c, "Failed to create coupon")
		return
	}
	utils.Created(c, doc)
}

func (h *AdminHandler) UpdateCoupon(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	doc, err := h.appwrite.UpdateCoupon(c.Param("id"), body)
	if err != nil {
		utils.InternalError(c, "Failed to update coupon")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) DeleteCoupon(c *gin.Context) {
	if err := h.appwrite.DeleteCoupon(c.Param("id")); err != nil {
		utils.InternalError(c, "Failed to delete coupon")
		return
	}
	utils.Success(c, gin.H{"message": "Coupon deleted"})
}

// ═══════════════════════════════════════════════════════════════════════════════
// REVIEWS
// ═══════════════════════════════════════════════════════════════════════════════

func (h *AdminHandler) ListReviews(c *gin.Context) {
	p := models.ParsePagination(c)
	queries := []string{
		appwrite.QueryLimit(p.PerPage),
		appwrite.QueryOffset(p.Offset()),
		appwrite.QueryOrderDesc("created_at"),
	}
	result, err := h.appwrite.ListReviewsByQuery(queries)
	if err != nil {
		utils.InternalError(c, "Failed to list reviews")
		return
	}
	utils.Paginated(c, result.Documents, p.Page, p.PerPage, result.Total)
}

func (h *AdminHandler) UpdateReview(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	doc, err := h.appwrite.UpdateReview(c.Param("id"), body)
	if err != nil {
		utils.InternalError(c, "Failed to update review")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) DeleteReview(c *gin.Context) {
	if err := h.appwrite.DeleteReview(c.Param("id")); err != nil {
		utils.InternalError(c, "Failed to delete review")
		return
	}
	utils.Success(c, gin.H{"message": "Review deleted"})
}

// ═══════════════════════════════════════════════════════════════════════════════
// GOLD SUBSCRIPTIONS
// ═══════════════════════════════════════════════════════════════════════════════

func (h *AdminHandler) ListGoldSubscriptions(c *gin.Context) {
	p := models.ParsePagination(c)
	queries := []string{
		appwrite.QueryLimit(p.PerPage),
		appwrite.QueryOffset(p.Offset()),
		appwrite.QueryOrderDesc("$createdAt"),
	}
	if status := c.Query("status"); status != "" {
		queries = append(queries, appwrite.QueryEqual("status", status))
	}
	result, err := h.appwrite.ListAllGoldSubscriptions(queries)
	if err != nil {
		utils.InternalError(c, "Failed to list gold subscriptions")
		return
	}
	utils.Paginated(c, result.Documents, p.Page, p.PerPage, result.Total)
}

func (h *AdminHandler) GoldStats(c *gin.Context) {
	active, _ := h.appwrite.ListAllGoldSubscriptions([]string{
		appwrite.QueryEqual("status", "active"),
		appwrite.QueryLimit(1),
	})
	all, _ := h.appwrite.ListAllGoldSubscriptions([]string{
		appwrite.QueryLimit(1),
	})
	totalActive := 0
	totalAll := 0
	if active != nil {
		totalActive = active.Total
	}
	if all != nil {
		totalAll = all.Total
	}
	utils.Success(c, gin.H{
		"total_subscriptions": totalAll,
		"active":              totalActive,
	})
}

// ═══════════════════════════════════════════════════════════════════════════════
// REFERRALS
// ═══════════════════════════════════════════════════════════════════════════════

func (h *AdminHandler) ListReferrals(c *gin.Context) {
	p := models.ParsePagination(c)
	queries := []string{
		appwrite.QueryLimit(p.PerPage),
		appwrite.QueryOffset(p.Offset()),
		appwrite.QueryOrderDesc("$createdAt"),
	}
	result, err := h.appwrite.ListAllReferrals(queries)
	if err != nil {
		utils.InternalError(c, "Failed to list referrals")
		return
	}
	utils.Paginated(c, result.Documents, p.Page, p.PerPage, result.Total)
}

func (h *AdminHandler) ReferralStats(c *gin.Context) {
	all, _ := h.appwrite.ListAllReferrals([]string{appwrite.QueryLimit(1)})
	completed, _ := h.appwrite.ListAllReferrals([]string{
		appwrite.QueryEqual("status", "completed"),
		appwrite.QueryLimit(1),
	})
	totalAll := 0
	totalCompleted := 0
	if all != nil {
		totalAll = all.Total
	}
	if completed != nil {
		totalCompleted = completed.Total
	}
	utils.Success(c, gin.H{
		"total_referrals":     totalAll,
		"completed_referrals": totalCompleted,
	})
}

// ═══════════════════════════════════════════════════════════════════════════════
// NOTIFICATIONS
// ═══════════════════════════════════════════════════════════════════════════════

func (h *AdminHandler) BroadcastNotification(c *gin.Context) {
	var body struct {
		Title    string `json:"title" binding:"required"`
		Body     string `json:"body" binding:"required"`
		Type     string `json:"type"`
		TargetID string `json:"target_id"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Title and body are required")
		return
	}
	nType := body.Type
	if nType == "" {
		nType = "system"
	}
	id := fmt.Sprintf("notif_%s", uuid.New().String()[:8])
	doc, err := h.appwrite.CreateNotification(id, map[string]interface{}{
		"user_id":    body.TargetID, // empty = broadcast
		"type":       nType,
		"title":      body.Title,
		"body":       body.Body,
		"is_read":    false,
		"created_at": time.Now().Format(time.RFC3339),
	})
	if err != nil {
		utils.InternalError(c, "Failed to send notification")
		return
	}
	utils.Created(c, doc)
}

func (h *AdminHandler) NotificationHistory(c *gin.Context) {
	p := models.ParsePagination(c)
	queries := []string{
		appwrite.QueryOrderDesc("created_at"),
		appwrite.QueryLimit(p.PerPage),
		appwrite.QueryOffset(p.Offset()),
	}
	result, err := h.appwrite.ListAllNotifications(queries)
	if err != nil {
		utils.InternalError(c, "Failed to list notifications")
		return
	}
	utils.Paginated(c, result.Documents, p.Page, p.PerPage, result.Total)
}

// ═══════════════════════════════════════════════════════════════════════════════
// DISPUTES (delivery_issues)
// ═══════════════════════════════════════════════════════════════════════════════

func (h *AdminHandler) ListDisputes(c *gin.Context) {
	p := models.ParsePagination(c)
	queries := []string{
		appwrite.QueryOrderDesc("$createdAt"),
		appwrite.QueryLimit(p.PerPage),
		appwrite.QueryOffset(p.Offset()),
	}
	result, err := h.appwrite.ListDeliveryIssuesByQuery(queries)
	if err != nil {
		utils.InternalError(c, "Failed to list disputes")
		return
	}
	docs := []map[string]interface{}{}
	total := 0
	if result != nil {
		docs = result.Documents
		total = result.Total
	}
	utils.Paginated(c, docs, p.Page, p.PerPage, total)
}

func (h *AdminHandler) GetDispute(c *gin.Context) {
	doc, err := h.appwrite.GetDeliveryIssue(c.Param("id"))
	if err != nil {
		utils.NotFound(c, "Dispute not found")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) UpdateDispute(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	doc, err := h.appwrite.UpdateDeliveryIssue(c.Param("id"), body)
	if err != nil {
		utils.InternalError(c, "Failed to update dispute")
		return
	}
	utils.Success(c, doc)
}

// ═══════════════════════════════════════════════════════════════════════════════
// ADMIN ACCOUNTS (users with admin/super_admin role)
// ═══════════════════════════════════════════════════════════════════════════════

func (h *AdminHandler) ListAdmins(c *gin.Context) {
	// Fetch admin + super_admin users
	admins, err := h.appwrite.ListUsers([]string{
		appwrite.QueryEqual("role", "admin"),
		appwrite.QueryLimit(100),
	})
	superAdmins, _ := h.appwrite.ListUsers([]string{
		appwrite.QueryEqual("role", "super_admin"),
		appwrite.QueryLimit(100),
	})
	if err != nil {
		utils.InternalError(c, "Failed to list admins")
		return
	}
	all := []map[string]interface{}{}
	if admins != nil {
		all = append(all, admins.Documents...)
	}
	if superAdmins != nil {
		all = append(all, superAdmins.Documents...)
	}
	utils.Success(c, all)
}

func (h *AdminHandler) CreateAdmin(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	// Ensure role is admin
	if _, ok := body["role"]; !ok {
		body["role"] = "admin"
	}
	role, _ := body["role"].(string)
	if role != "admin" && role != "super_admin" {
		body["role"] = "admin"
	}
	id := fmt.Sprintf("admin_%s", uuid.New().String()[:8])
	doc, err := h.appwrite.CreateUser(id, body)
	if err != nil {
		utils.InternalError(c, "Failed to create admin")
		return
	}
	utils.Created(c, doc)
}

func (h *AdminHandler) UpdateAdmin(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	doc, err := h.appwrite.UpdateUser(c.Param("id"), body)
	if err != nil {
		utils.InternalError(c, "Failed to update admin")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) DeleteAdmin(c *gin.Context) {
	// Prevent self-deletion
	if c.Param("id") == middleware.GetUserID(c) {
		utils.BadRequest(c, "Cannot delete your own account")
		return
	}
	if err := h.appwrite.DeleteUser(c.Param("id")); err != nil {
		utils.InternalError(c, "Failed to delete admin")
		return
	}
	utils.Success(c, gin.H{"message": "Admin deleted"})
}

// ═══════════════════════════════════════════════════════════════════════════════
// LIVE DATA
// ═══════════════════════════════════════════════════════════════════════════════

func (h *AdminHandler) LiveSessions(c *gin.Context) {
	// Return online users from delivery partners
	online, _ := h.appwrite.ListDeliveryPartners([]string{
		appwrite.QueryEqual("is_online", true),
		appwrite.QueryLimit(100),
	})
	riders := 0
	if online != nil {
		riders = online.Total
	}
	utils.Success(c, gin.H{
		"online_riders": riders,
	})
}

func (h *AdminHandler) LiveRiders(c *gin.Context) {
	result, err := h.appwrite.ListDeliveryLocations([]string{
		appwrite.QueryEqual("is_online", true),
		appwrite.QueryLimit(500),
	})
	if err != nil {
		utils.InternalError(c, "Failed to get rider locations")
		return
	}
	docs := []map[string]interface{}{}
	if result != nil {
		docs = result.Documents
	}
	utils.Success(c, docs)
}

func (h *AdminHandler) LiveOrders(c *gin.Context) {
	result, err := h.appwrite.ListOrders([]string{
		appwrite.QueryNotEqual("status", "delivered", "cancelled"),
		appwrite.QueryOrderDesc("placed_at"),
		appwrite.QueryLimit(100),
	})
	if err != nil {
		utils.InternalError(c, "Failed to get live orders")
		return
	}
	docs := []map[string]interface{}{}
	if result != nil {
		docs = result.Documents
	}
	utils.Success(c, docs)
}

// ═══════════════════════════════════════════════════════════════════════════════
// GENERIC COLLECTION ENDPOINTS (zones, surge, flags, audit, support, content, settings)
// These use the generic ListDocuments/CreateDocument/etc. methods.
// If the Appwrite collection doesn't exist yet, they gracefully return empty.
// ═══════════════════════════════════════════════════════════════════════════════

// --- Audit Log ---

func (h *AdminHandler) ListAuditLog(c *gin.Context) {
	p := models.ParsePagination(c)
	docs, total := h.safeList(models.CollectionAuditLog, []string{
		appwrite.QueryOrderDesc("$createdAt"),
		appwrite.QueryLimit(p.PerPage),
		appwrite.QueryOffset(p.Offset()),
	})
	utils.Paginated(c, docs, p.Page, p.PerPage, total)
}

// --- Zones ---

func (h *AdminHandler) ListZones(c *gin.Context) {
	docs, _ := h.safeList(models.CollectionZones, []string{appwrite.QueryLimit(500)})
	utils.Success(c, docs)
}

func (h *AdminHandler) CreateZone(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	id := fmt.Sprintf("zone_%s", uuid.New().String()[:8])
	doc, err := h.appwrite.CreateDocument(models.CollectionZones, id, body)
	if err != nil {
		log.Printf("CreateZone error: %v", err)
		utils.InternalError(c, "Failed to create zone")
		return
	}
	utils.Created(c, doc)
}

func (h *AdminHandler) UpdateZone(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	doc, err := h.appwrite.UpdateDocument(models.CollectionZones, c.Param("id"), body)
	if err != nil {
		utils.InternalError(c, "Failed to update zone")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) DeleteZone(c *gin.Context) {
	if err := h.appwrite.DeleteDocument(models.CollectionZones, c.Param("id")); err != nil {
		utils.InternalError(c, "Failed to delete zone")
		return
	}
	utils.Success(c, gin.H{"message": "Zone deleted"})
}

// --- Surge Rules ---

func (h *AdminHandler) ListSurge(c *gin.Context) {
	docs, _ := h.safeList(models.CollectionSurgeRules, []string{appwrite.QueryLimit(500)})
	utils.Success(c, docs)
}

func (h *AdminHandler) CreateSurge(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	id := fmt.Sprintf("surge_%s", uuid.New().String()[:8])
	doc, err := h.appwrite.CreateDocument(models.CollectionSurgeRules, id, body)
	if err != nil {
		log.Printf("CreateSurge error: %v", err)
		utils.InternalError(c, "Failed to create surge rule")
		return
	}
	utils.Created(c, doc)
}

func (h *AdminHandler) UpdateSurge(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	doc, err := h.appwrite.UpdateDocument(models.CollectionSurgeRules, c.Param("id"), body)
	if err != nil {
		utils.InternalError(c, "Failed to update surge rule")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) DeleteSurge(c *gin.Context) {
	if err := h.appwrite.DeleteDocument(models.CollectionSurgeRules, c.Param("id")); err != nil {
		utils.InternalError(c, "Failed to delete surge rule")
		return
	}
	utils.Success(c, gin.H{"message": "Surge rule deleted"})
}

// --- Feature Flags ---

func (h *AdminHandler) ListFeatureFlags(c *gin.Context) {
	docs, _ := h.safeList(models.CollectionFeatureFlags, []string{appwrite.QueryLimit(500)})
	utils.Success(c, docs)
}

func (h *AdminHandler) UpdateFeatureFlag(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	doc, err := h.appwrite.UpdateDocument(models.CollectionFeatureFlags, c.Param("key"), body)
	if err != nil {
		utils.InternalError(c, "Failed to update feature flag")
		return
	}
	utils.Success(c, doc)
}

// --- Support Issues ---

func (h *AdminHandler) ListSupportIssues(c *gin.Context) {
	p := models.ParsePagination(c)
	docs, total := h.safeList(models.CollectionSupportIssues, []string{
		appwrite.QueryOrderDesc("$createdAt"),
		appwrite.QueryLimit(p.PerPage),
		appwrite.QueryOffset(p.Offset()),
	})
	utils.Paginated(c, docs, p.Page, p.PerPage, total)
}

func (h *AdminHandler) GetSupportIssue(c *gin.Context) {
	doc, err := h.appwrite.GetDocument(models.CollectionSupportIssues, c.Param("id"))
	if err != nil {
		utils.NotFound(c, "Support issue not found")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) UpdateSupportIssue(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	doc, err := h.appwrite.UpdateDocument(models.CollectionSupportIssues, c.Param("id"), body)
	if err != nil {
		utils.InternalError(c, "Failed to update support issue")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) SupportIssueMessages(c *gin.Context) {
	// Messages are embedded or can be a sub-collection; return the issue with messages field
	doc, err := h.appwrite.GetDocument(models.CollectionSupportIssues, c.Param("id"))
	if err != nil {
		utils.NotFound(c, "Support issue not found")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) ReplySupportIssue(c *gin.Context) {
	var body struct {
		Message string `json:"message" binding:"required"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Message is required")
		return
	}
	adminID := middleware.GetUserID(c)
	// Append reply as update; actual implementation depends on Appwrite schema
	doc, err := h.appwrite.UpdateDocument(models.CollectionSupportIssues, c.Param("id"), map[string]interface{}{
		"last_reply":    body.Message,
		"last_reply_by": adminID,
		"last_reply_at": time.Now().Format(time.RFC3339),
	})
	if err != nil {
		utils.InternalError(c, "Failed to reply to support issue")
		return
	}
	utils.Success(c, doc)
}

// --- Content / Banners ---

func (h *AdminHandler) ListBanners(c *gin.Context) {
	docs, _ := h.safeList(models.CollectionBanners, []string{appwrite.QueryLimit(500)})
	utils.Success(c, docs)
}

func (h *AdminHandler) CreateBanner(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	id := fmt.Sprintf("banner_%s", uuid.New().String()[:8])
	doc, err := h.appwrite.CreateDocument(models.CollectionBanners, id, body)
	if err != nil {
		log.Printf("CreateBanner error: %v", err)
		utils.InternalError(c, "Failed to create banner")
		return
	}
	utils.Created(c, doc)
}

func (h *AdminHandler) UpdateBanner(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	doc, err := h.appwrite.UpdateDocument(models.CollectionBanners, c.Param("id"), body)
	if err != nil {
		utils.InternalError(c, "Failed to update banner")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) DeleteBanner(c *gin.Context) {
	if err := h.appwrite.DeleteDocument(models.CollectionBanners, c.Param("id")); err != nil {
		utils.InternalError(c, "Failed to delete banner")
		return
	}
	utils.Success(c, gin.H{"message": "Banner deleted"})
}

func (h *AdminHandler) ListContentCategories(c *gin.Context) {
	// Return all menu categories across restaurants
	docs, _ := h.safeList(models.CollectionMenuCategories, []string{
		appwrite.QueryLimit(500),
	})
	utils.Success(c, docs)
}

// --- Settings ---

func (h *AdminHandler) GetSettings(c *gin.Context) {
	docs, _ := h.safeList(models.CollectionSettings, []string{appwrite.QueryLimit(1)})
	if len(docs) > 0 {
		utils.Success(c, docs[0])
	} else {
		// Return defaults
		utils.Success(c, gin.H{
			"platform_name":    "Chizze",
			"commission_rate":  15.0,
			"delivery_radius":  10.0,
			"min_order_value":  99.0,
			"support_email":    "support@chizze.app",
			"support_phone":    "+919876543210",
		})
	}
}

func (h *AdminHandler) UpdateSettings(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	// Try to update existing settings doc, or create one
	docs, _ := h.safeList(models.CollectionSettings, []string{appwrite.QueryLimit(1)})
	if len(docs) > 0 {
		id, _ := docs[0]["$id"].(string)
		doc, err := h.appwrite.UpdateDocument(models.CollectionSettings, id, body)
		if err != nil {
			utils.InternalError(c, "Failed to update settings")
			return
		}
		utils.Success(c, doc)
	} else {
		id := "platform_settings"
		doc, err := h.appwrite.CreateDocument(models.CollectionSettings, id, body)
		if err != nil {
			log.Printf("CreateSettings error (collection may not exist): %v", err)
			utils.InternalError(c, "Failed to save settings")
			return
		}
		utils.Success(c, doc)
	}
}

// logAudit is a helper that writes an audit log entry (best-effort, non-blocking)
func (h *AdminHandler) logAudit(adminID, action, summary string) {
	id := fmt.Sprintf("audit_%s", uuid.New().String()[:8])
	_, err := h.appwrite.CreateDocument(models.CollectionAuditLog, id, map[string]interface{}{
		"admin_id":   adminID,
		"admin_name": "",
		"action":     action,
		"summary":    summary,
		"created_at": time.Now().Format(time.RFC3339),
	})
	if err != nil {
		log.Printf("Audit log write failed (non-critical): %v", err)
	}
}

// ═══════════════════════════════════════════════════════════════════════════════
// UNUSED IMPORT GUARD
// ═══════════════════════════════════════════════════════════════════════════════

var _ = strings.TrimSpace
