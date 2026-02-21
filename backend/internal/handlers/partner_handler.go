package handlers

import (
	"encoding/json"
	"fmt"
	"sort"
	"time"

	"github.com/chizze/backend/internal/middleware"
	"github.com/chizze/backend/internal/models"
	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/pkg/appwrite"
	"github.com/chizze/backend/pkg/utils"
	"github.com/gin-gonic/gin"
)

// PartnerHandler handles restaurant partner-specific endpoints
type PartnerHandler struct {
	appwrite *services.AppwriteService
}

// NewPartnerHandler creates a partner handler
func NewPartnerHandler(aw *services.AppwriteService) *PartnerHandler {
	return &PartnerHandler{appwrite: aw}
}

// getPartnerRestaurant looks up the restaurant owned by the current user
func (h *PartnerHandler) getPartnerRestaurant(c *gin.Context) (map[string]interface{}, string, bool) {
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

// Dashboard returns partner dashboard metrics
// GET /api/v1/partner/dashboard
func (h *PartnerHandler) Dashboard(c *gin.Context) {
	restaurant, restID, ok := h.getPartnerRestaurant(c)
	if !ok {
		return
	}

	// Get today's date range in RFC3339
	now := time.Now()
	todayStart := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	todayStartStr := todayStart.Format(time.RFC3339)

	// Fetch today's orders for this restaurant
	queries := []string{
		appwrite.QueryEqual("restaurant_id", restID),
		appwrite.QueryGreaterThanEqual("placed_at", todayStartStr),
		appwrite.QueryLimit(500),
	}

	orderResult, err := h.appwrite.ListOrders(queries)
	if err != nil {
		utils.InternalError(c, "Failed to fetch orders")
		return
	}

	// Calculate metrics
	todayRevenue := 0.0
	todayOrders := len(orderResult.Documents)
	pendingOrders := 0

	for _, order := range orderResult.Documents {
		status, _ := order["status"].(string)

		// Revenue = orders that are not cancelled
		if status != models.OrderStatusCancelled {
			grandTotal := getFloat(order, "grand_total")
			todayRevenue += grandTotal
		}

		// Pending = placed or confirmed (not yet preparing)
		if status == models.OrderStatusPlaced || status == models.OrderStatusConfirmed {
			pendingOrders++
		}
	}

	rating, _ := restaurant["rating"].(float64)
	isOnline, _ := restaurant["is_online"].(bool)
	name, _ := restaurant["name"].(string)

	utils.Success(c, gin.H{
		"restaurant_id":   restID,
		"restaurant_name": name,
		"is_online":       isOnline,
		"today_revenue":   todayRevenue,
		"today_orders":    todayOrders,
		"avg_rating":      rating,
		"pending_orders":  pendingOrders,
	})
}

// ListOrders returns orders for the partner's restaurant with status filtering
// GET /api/v1/partner/orders?status=placed&page=1&per_page=20
func (h *PartnerHandler) ListOrders(c *gin.Context) {
	_, restID, ok := h.getPartnerRestaurant(c)
	if !ok {
		return
	}

	pg := models.ParsePagination(c)

	queries := []string{
		appwrite.QueryEqual("restaurant_id", restID),
		appwrite.QueryOrderDesc("placed_at"),
		appwrite.QueryLimit(pg.PerPage),
		appwrite.QueryOffset(pg.Offset()),
	}

	// Optional status filter
	if status := c.Query("status"); status != "" {
		queries = append(queries, appwrite.QueryEqual("status", status))
	}

	// Optional date range filter
	if fromDate := c.Query("from"); fromDate != "" {
		queries = append(queries, appwrite.QueryGreaterThanEqual("placed_at", fromDate))
	}
	if toDate := c.Query("to"); toDate != "" {
		queries = append(queries, appwrite.QueryLessThanEqual("placed_at", toDate))
	}

	result, err := h.appwrite.ListOrders(queries)
	if err != nil {
		utils.InternalError(c, "Failed to fetch orders")
		return
	}

	// Enrich orders with accept deadline (90 seconds from placed_at for new orders)
	enriched := make([]map[string]interface{}, 0, len(result.Documents))
	for _, order := range result.Documents {
		status, _ := order["status"].(string)
		if status == models.OrderStatusPlaced {
			placedAtStr, _ := order["placed_at"].(string)
			if t, err := time.Parse(time.RFC3339, placedAtStr); err == nil {
				deadline := t.Add(90 * time.Second)
				order["accept_deadline"] = deadline.Format(time.RFC3339)
				order["is_new"] = true
			}
		} else {
			order["is_new"] = false
		}
		enriched = append(enriched, order)
	}

	utils.Paginated(c, enriched, pg.Page, pg.PerPage, result.Total)
}

// Analytics returns revenue trends, top items, and peak hours for the partner
// GET /api/v1/partner/analytics?period=week (day|week|month)
func (h *PartnerHandler) Analytics(c *gin.Context) {
	_, restID, ok := h.getPartnerRestaurant(c)
	if !ok {
		return
	}

	period := c.DefaultQuery("period", "week")

	now := time.Now()
	var fromDate time.Time
	switch period {
	case "day":
		fromDate = time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	case "month":
		fromDate = time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, now.Location())
	default: // week
		fromDate = now.AddDate(0, 0, -7)
	}
	fromDateStr := fromDate.Format(time.RFC3339)

	// Fetch orders in the period
	queries := []string{
		appwrite.QueryEqual("restaurant_id", restID),
		appwrite.QueryGreaterThanEqual("placed_at", fromDateStr),
		appwrite.QueryNotEqual("status", models.OrderStatusCancelled),
		appwrite.QueryLimit(1000),
	}

	orderResult, err := h.appwrite.ListOrders(queries)
	if err != nil {
		utils.InternalError(c, "Failed to fetch orders for analytics")
		return
	}

	// Aggregate metrics
	totalRevenue := 0.0
	totalOrders := len(orderResult.Documents)
	dailyRevenueMap := make(map[string]float64) // "Mon" => amount
	dailyOrdersMap := make(map[string]int)
	hourlyOrders := make(map[int]int)           // hour => count
	itemCountMap := make(map[string]int)         // item_name => order_count
	itemRevenueMap := make(map[string]float64)   // item_name => revenue
	itemVegMap := make(map[string]bool)           // item_name => is_veg

	for _, order := range orderResult.Documents {
		grandTotal := getFloat(order, "grand_total")
		totalRevenue += grandTotal

		// Daily aggregation
		placedAtStr, _ := order["placed_at"].(string)
		if t, err := time.Parse(time.RFC3339, placedAtStr); err == nil {
			dayKey := t.Weekday().String()[:3] // "Mon", "Tue", etc.
			dailyRevenueMap[dayKey] += grandTotal
			dailyOrdersMap[dayKey]++
			hourlyOrders[t.Hour()]++
		}

		// Item aggregation — parse items JSON
		itemsJSON, _ := order["items"].(string)
		if itemsJSON != "" {
			var items []map[string]interface{}
			if json.Unmarshal([]byte(itemsJSON), &items) == nil {
				for _, item := range items {
					name, _ := item["name"].(string)
					qty := 1
					if q, ok := item["quantity"].(float64); ok {
						qty = int(q)
					}
					price := 0.0
					if p, ok := item["price"].(float64); ok {
						price = p
					}
					isVeg, _ := item["is_veg"].(bool)

					itemCountMap[name] += qty
					itemRevenueMap[name] += price * float64(qty)
					itemVegMap[name] = isVeg
				}
			}
		}
	}

	// Build daily revenue list (sorted by weekday)
	weekdays := []string{"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"}
	dailyRevenue := make([]gin.H, 0, 7)
	for _, day := range weekdays {
		dailyRevenue = append(dailyRevenue, gin.H{
			"day":    day,
			"amount": dailyRevenueMap[day],
			"orders": dailyOrdersMap[day],
		})
	}

	// Build top items (sorted by order count descending, top 10)
	type topItem struct {
		Name   string  `json:"name"`
		Count  int     `json:"order_count"`
		Rev    float64 `json:"revenue"`
		IsVeg  bool    `json:"is_veg"`
	}
	topItems := make([]topItem, 0, len(itemCountMap))
	for name, count := range itemCountMap {
		topItems = append(topItems, topItem{
			Name:  name,
			Count: count,
			Rev:   itemRevenueMap[name],
			IsVeg: itemVegMap[name],
		})
	}
	sort.Slice(topItems, func(i, j int) bool {
		return topItems[i].Count > topItems[j].Count
	})
	if len(topItems) > 10 {
		topItems = topItems[:10]
	}

	// Build peak hours (sorted by hour)
	peakHours := make([]gin.H, 0)
	for hour := 0; hour < 24; hour++ {
		if count, exists := hourlyOrders[hour]; exists && count > 0 {
			peakHours = append(peakHours, gin.H{
				"hour":   hour,
				"orders": count,
			})
		}
	}

	avgOrderValue := 0.0
	if totalOrders > 0 {
		avgOrderValue = totalRevenue / float64(totalOrders)
	}

	utils.Success(c, gin.H{
		"period":          period,
		"total_revenue":   totalRevenue,
		"total_orders":    totalOrders,
		"avg_order_value": avgOrderValue,
		"revenue_data":    dailyRevenue,
		"top_items":       topItems,
		"peak_hours":      peakHours,
	})
}

// ToggleOnline toggles the restaurant's online/offline status
// PUT /api/v1/partner/restaurant/status
func (h *PartnerHandler) ToggleOnline(c *gin.Context) {
	restaurant, restID, ok := h.getPartnerRestaurant(c)
	if !ok {
		return
	}

	var req struct {
		IsOnline *bool `json:"is_online"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || req.IsOnline == nil {
		// Toggle current state if no body
		currentOnline, _ := restaurant["is_online"].(bool)
		newState := !currentOnline
		req.IsOnline = &newState
	}

	updated, err := h.appwrite.UpdateRestaurant(restID, map[string]interface{}{
		"is_online": *req.IsOnline,
	})
	if err != nil {
		utils.InternalError(c, "Failed to update restaurant status")
		return
	}
	utils.Success(c, gin.H{
		"is_online": *req.IsOnline,
		"message":   fmt.Sprintf("Restaurant is now %s", boolToStatus(*req.IsOnline)),
	})
	_ = updated
}

// ListCategories returns menu categories for the partner's restaurant
// GET /api/v1/partner/categories
func (h *PartnerHandler) ListCategories(c *gin.Context) {
	_, restID, ok := h.getPartnerRestaurant(c)
	if !ok {
		return
	}

	cats, err := h.appwrite.ListMenuCategories(restID)
	if err != nil {
		utils.InternalError(c, "Failed to fetch categories")
		return
	}
	utils.Success(c, gin.H{"categories": cats.Documents, "total": cats.Total})
}

// CreateCategory creates a new menu category
// POST /api/v1/partner/categories
func (h *PartnerHandler) CreateCategory(c *gin.Context) {
	_, restID, ok := h.getPartnerRestaurant(c)
	if !ok {
		return
	}

	var req struct {
		Name      string `json:"name" binding:"required"`
		SortOrder int    `json:"sort_order"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Category name is required")
		return
	}

	data := map[string]interface{}{
		"restaurant_id": restID,
		"name":          req.Name,
		"sort_order":    req.SortOrder,
		"is_active":     true,
	}

	doc, err := h.appwrite.CreateMenuCategory("unique()", data)
	if err != nil {
		utils.InternalError(c, "Failed to create category")
		return
	}
	utils.Created(c, doc)
}

// UpdateCategory updates a menu category
// PUT /api/v1/partner/categories/:id
func (h *PartnerHandler) UpdateCategory(c *gin.Context) {
	_, restID, ok := h.getPartnerRestaurant(c)
	if !ok {
		return
	}

	catID := c.Param("id")

	// Verify ownership
	cat, err := h.appwrite.GetMenuCategory(catID)
	if err != nil {
		utils.NotFound(c, "Category not found")
		return
	}
	catRestID, _ := cat["restaurant_id"].(string)
	if catRestID != restID {
		utils.Forbidden(c, "This category does not belong to your restaurant")
		return
	}

	var req map[string]interface{}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Invalid data")
		return
	}

	delete(req, "restaurant_id")
	delete(req, "$id")

	doc, err := h.appwrite.UpdateMenuCategory(catID, req)
	if err != nil {
		utils.InternalError(c, "Failed to update category")
		return
	}
	utils.Success(c, doc)
}

// DeleteCategory deletes a menu category (and marks items as uncategorized)
// DELETE /api/v1/partner/categories/:id
func (h *PartnerHandler) DeleteCategory(c *gin.Context) {
	_, restID, ok := h.getPartnerRestaurant(c)
	if !ok {
		return
	}

	catID := c.Param("id")

	cat, err := h.appwrite.GetMenuCategory(catID)
	if err != nil {
		utils.NotFound(c, "Category not found")
		return
	}
	catRestID, _ := cat["restaurant_id"].(string)
	if catRestID != restID {
		utils.Forbidden(c, "This category does not belong to your restaurant")
		return
	}

	if err := h.appwrite.DeleteMenuCategory(catID); err != nil {
		utils.InternalError(c, "Failed to delete category")
		return
	}

	utils.Success(c, gin.H{"message": "Category deleted"})
}

// Performance returns preparation time and acceptance metrics
// GET /api/v1/partner/performance
func (h *PartnerHandler) Performance(c *gin.Context) {
	_, restID, ok := h.getPartnerRestaurant(c)
	if !ok {
		return
	}

	// Get last 7 days of orders
	fromDate := time.Now().AddDate(0, 0, -7).Format(time.RFC3339)
	queries := []string{
		appwrite.QueryEqual("restaurant_id", restID),
		appwrite.QueryGreaterThanEqual("placed_at", fromDate),
		appwrite.QueryLimit(1000),
	}

	result, err := h.appwrite.ListOrders(queries)
	if err != nil {
		utils.InternalError(c, "Failed to fetch performance data")
		return
	}

	totalOrders := len(result.Documents)
	cancelledOrders := 0
	totalPrepTimeMin := 0.0
	prepCount := 0

	for _, order := range result.Documents {
		status, _ := order["status"].(string)
		if status == models.OrderStatusCancelled {
			cancelledOrders++
			continue
		}

		// Calculate prep time (confirmed_at → prepared_at)
		confirmedStr, _ := order["confirmed_at"].(string)
		preparedStr, _ := order["prepared_at"].(string)
		if confirmedStr != "" && preparedStr != "" {
			confirmedAt, e1 := time.Parse(time.RFC3339, confirmedStr)
			preparedAt, e2 := time.Parse(time.RFC3339, preparedStr)
			if e1 == nil && e2 == nil {
				prepTime := preparedAt.Sub(confirmedAt).Minutes()
				if prepTime > 0 && prepTime < 180 { // sanity: < 3 hours
					totalPrepTimeMin += prepTime
					prepCount++
				}
			}
		}
	}

	acceptedOrders := totalOrders - cancelledOrders
	acceptanceRate := 0.0
	cancellationRate := 0.0
	avgPrepTime := 0.0
	if totalOrders > 0 {
		acceptanceRate = float64(acceptedOrders) / float64(totalOrders) * 100
		cancellationRate = float64(cancelledOrders) / float64(totalOrders) * 100
	}
	if prepCount > 0 {
		avgPrepTime = totalPrepTimeMin / float64(prepCount)
	}

	utils.Success(c, gin.H{
		"total_orders":      totalOrders,
		"accepted_orders":   acceptedOrders,
		"cancelled_orders":  cancelledOrders,
		"acceptance_rate":   acceptanceRate,
		"cancellation_rate": cancellationRate,
		"avg_prep_time_min": avgPrepTime,
	})
}

func boolToStatus(b bool) string {
	if b {
		return "online"
	}
	return "offline"
}
