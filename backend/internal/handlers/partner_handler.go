package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/chizze/backend/internal/middleware"
	"github.com/chizze/backend/internal/models"
	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/pkg/appwrite"
	redispkg "github.com/chizze/backend/pkg/redis"
	"github.com/chizze/backend/pkg/utils"
	"github.com/gin-gonic/gin"
)

// upiVPARegex validates UPI Virtual Payment Address format (localpart@provider)
var upiVPARegex = regexp.MustCompile(`^[a-zA-Z0-9._-]+@[a-zA-Z][a-zA-Z0-9]+$`)

// PartnerHandler handles restaurant partner-specific endpoints
type PartnerHandler struct {
	appwrite *services.AppwriteService
	redis    *redispkg.Client
}

// NewPartnerHandler creates a partner handler
func NewPartnerHandler(aw *services.AppwriteService, redis *redispkg.Client) *PartnerHandler {
	return &PartnerHandler{appwrite: aw, redis: redis}
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
// @Summary      Get partner dashboard
// @Description  Returns dashboard metrics including today's revenue, order count, pending orders, and rating
// @Tags         Partners
// @Accept       json
// @Produce      json
// @Success      200  {object}  map[string]interface{}
// @Failure      403  {object}  map[string]interface{}
// @Failure      500  {object}  map[string]interface{}
// @Security     BearerAuth
// @Router       /api/v1/partner/dashboard [get]
func (h *PartnerHandler) Dashboard(c *gin.Context) {
	restaurant, restID, ok := h.getPartnerRestaurant(c)
	if !ok {
		return
	}

	// Short-lived cache to absorb the partner app's 5s polling storm.
	// TTL below the poll interval is intentional: each partner refreshes at most
	// once per TTL window, so staleness is bounded and invalidation is unnecessary.
	cacheKey := "partner:dashboard:" + restID
	if h.redis != nil {
		if cached, err := h.redis.Get(c.Request.Context(), cacheKey); err == nil && cached != "" {
			var payload gin.H
			if json.Unmarshal([]byte(cached), &payload) == nil {
				utils.Success(c, payload)
				return
			}
		}
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

	coverImageUrl, _ := restaurant["cover_image_url"].(string)

	payload := gin.H{
		"restaurant_id":        restID,
		"restaurant_name":      name,
		"is_online":            isOnline,
		"today_revenue":        todayRevenue,
		"today_orders":         todayOrders,
		"avg_rating":           rating,
		"pending_orders":       pendingOrders,
		"restaurant_image_url": coverImageUrl,
	}
	if h.redis != nil {
		if b, err := json.Marshal(payload); err == nil {
			_ = h.redis.Set(c.Request.Context(), cacheKey, string(b), 3*time.Second)
		}
	}
	utils.Success(c, payload)
}

// ListOrders returns orders for the partner's restaurant with status filtering
// @Summary      List partner orders
// @Description  Returns orders for the partner's restaurant with optional status, date range, and pagination filters
// @Tags         Partners
// @Accept       json
// @Produce      json
// @Param        status    query     string  false  "Filter by order status"
// @Param        from      query     string  false  "Start date (RFC3339)"
// @Param        to        query     string  false  "End date (RFC3339)"
// @Param        page      query     int     false  "Page number"
// @Param        per_page  query     int     false  "Items per page"
// @Success      200  {object}  map[string]interface{}
// @Failure      403  {object}  map[string]interface{}
// @Failure      500  {object}  map[string]interface{}
// @Security     BearerAuth
// @Router       /api/v1/partner/orders [get]
func (h *PartnerHandler) ListOrders(c *gin.Context) {
	_, restID, ok := h.getPartnerRestaurant(c)
	if !ok {
		return
	}

	pg := models.ParsePagination(c)
	statusFilter := c.Query("status")
	fromDate := c.Query("from")
	toDate := c.Query("to")

	// Short-lived cache for the partner app's 5s polling. TTL intentionally
	// under the poll interval; cache key scoped to every filter parameter.
	cacheKey := fmt.Sprintf("partner:orders:%s:p%d:l%d:s%s:f%s:t%s",
		restID, pg.Page, pg.PerPage, statusFilter, fromDate, toDate)
	if h.redis != nil {
		if cached, err := h.redis.Get(c.Request.Context(), cacheKey); err == nil && cached != "" {
			var payload struct {
				Data []map[string]interface{} `json:"data"`
				Meta struct {
					Page    int `json:"page"`
					PerPage int `json:"per_page"`
					Total   int `json:"total"`
				} `json:"meta"`
			}
			if json.Unmarshal([]byte(cached), &payload) == nil {
				utils.Paginated(c, payload.Data, payload.Meta.Page, payload.Meta.PerPage, payload.Meta.Total)
				return
			}
		}
	}

	queries := []string{
		appwrite.QueryEqual("restaurant_id", restID),
		appwrite.QueryOrderDesc("placed_at"),
		appwrite.QueryLimit(pg.PerPage),
		appwrite.QueryOffset(pg.Offset()),
	}

	if statusFilter != "" {
		queries = append(queries, appwrite.QueryEqual("status", statusFilter))
	}
	if fromDate != "" {
		queries = append(queries, appwrite.QueryGreaterThanEqual("placed_at", fromDate))
	}
	if toDate != "" {
		queries = append(queries, appwrite.QueryLessThanEqual("placed_at", toDate))
	}

	result, err := h.appwrite.ListOrders(queries)
	if err != nil {
		utils.InternalError(c, "Failed to fetch orders")
		return
	}

	// Collect customer IDs that need enrichment (missing denormalized name/phone)
	// so we can batch-fetch them in a single Appwrite query instead of N+1.
	missingIDSet := make(map[string]struct{})
	for _, order := range result.Documents {
		custID, _ := order["customer_id"].(string)
		if custID == "" {
			continue
		}
		name, _ := order["customer_name"].(string)
		phone, _ := order["customer_phone"].(string)
		if name == "" || phone == "" {
			missingIDSet[custID] = struct{}{}
		}
	}
	userByID := make(map[string]map[string]interface{}, len(missingIDSet))
	if len(missingIDSet) > 0 {
		ids := make([]string, 0, len(missingIDSet))
		for id := range missingIDSet {
			ids = append(ids, id)
		}
		if userList, uErr := h.appwrite.ListUsersByIDs(ids); uErr == nil && userList != nil {
			for _, u := range userList.Documents {
				if uid, _ := u["$id"].(string); uid != "" {
					userByID[uid] = u
				}
			}
		}
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

		// Fill missing customer name/phone from the batch-fetched user map.
		if custID, _ := order["customer_id"].(string); custID != "" {
			if user, ok := userByID[custID]; ok {
				if existing, _ := order["customer_name"].(string); existing == "" {
					if n, _ := user["name"].(string); n != "" {
						order["customer_name"] = n
					}
				}
				if existing, _ := order["customer_phone"].(string); existing == "" {
					if p, _ := user["phone"].(string); p != "" {
						order["customer_phone"] = p
					}
				}
			}
		}

		enriched = append(enriched, order)
	}

	if h.redis != nil {
		payload := map[string]interface{}{
			"data": enriched,
			"meta": map[string]interface{}{
				"page":     pg.Page,
				"per_page": pg.PerPage,
				"total":    result.Total,
			},
		}
		if b, err := json.Marshal(payload); err == nil {
			_ = h.redis.Set(c.Request.Context(), cacheKey, string(b), 3*time.Second)
		}
	}

	utils.Paginated(c, enriched, pg.Page, pg.PerPage, result.Total)
}

// Analytics returns revenue trends, top items, and peak hours for the partner
// @Summary      Get partner analytics
// @Description  Returns revenue trends, top selling items, and peak hours for the given period
// @Tags         Partners
// @Accept       json
// @Produce      json
// @Param        period  query     string  false  "Time period: day, week, or month"  default(week)
// @Success      200  {object}  map[string]interface{}
// @Failure      403  {object}  map[string]interface{}
// @Failure      500  {object}  map[string]interface{}
// @Security     BearerAuth
// @Router       /api/v1/partner/analytics [get]
func (h *PartnerHandler) Analytics(c *gin.Context) {
	_, restID, ok := h.getPartnerRestaurant(c)
	if !ok {
		return
	}

	period := c.DefaultQuery("period", "week")

	// 30-second Redis cache keyed on restaurant+period. Analytics data is
	// aggregate-across-1000-orders — not remotely real-time — and the partner
	// dashboard polls it on every screen focus. At 1000 concurrent partners
	// the raw path spawned a ListOrders(limit=1000) per hit, which
	// dominated our Appwrite quota.
	analyticsCacheKey := "partner_analytics:" + restID + ":" + period
	if h.redis != nil {
		if cached, err := h.redis.Get(c.Request.Context(), analyticsCacheKey); err == nil && cached != "" {
			var payload gin.H
			if jerr := json.Unmarshal([]byte(cached), &payload); jerr == nil {
				utils.Success(c, payload)
				return
			}
		}
	}

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

	analyticsPayload := gin.H{
		"period":          period,
		"total_revenue":   totalRevenue,
		"total_orders":    totalOrders,
		"avg_order_value": avgOrderValue,
		"revenue_data":    dailyRevenue,
		"top_items":       topItems,
		"peak_hours":      peakHours,
	}
	if h.redis != nil {
		if encoded, jerr := json.Marshal(analyticsPayload); jerr == nil {
			_ = h.redis.Set(c.Request.Context(), analyticsCacheKey, string(encoded), 30*time.Second)
		}
	}
	utils.Success(c, analyticsPayload)
}

// ToggleOnline toggles the restaurant's online/offline status
// @Summary      Toggle restaurant online status
// @Description  Toggles the restaurant's online/offline status. If no body is provided, the current state is inverted.
// @Tags         Partners
// @Accept       json
// @Produce      json
// @Param        body  body      object{is_online=bool}  false  "Optional explicit online state"
// @Success      200  {object}  map[string]interface{}
// @Failure      403  {object}  map[string]interface{}
// @Failure      500  {object}  map[string]interface{}
// @Security     BearerAuth
// @Router       /api/v1/partner/restaurant/status [put]
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
// @Summary      List menu categories
// @Description  Returns all menu categories for the partner's restaurant
// @Tags         Partners
// @Accept       json
// @Produce      json
// @Success      200  {object}  map[string]interface{}
// @Failure      403  {object}  map[string]interface{}
// @Failure      500  {object}  map[string]interface{}
// @Security     BearerAuth
// @Router       /api/v1/partner/categories [get]
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
// @Summary      Create a menu category
// @Description  Creates a new menu category for the partner's restaurant
// @Tags         Partners
// @Accept       json
// @Produce      json
// @Param        body  body      object{name=string,sort_order=int}  true  "Category data"
// @Success      201  {object}  map[string]interface{}
// @Failure      400  {object}  map[string]interface{}
// @Failure      403  {object}  map[string]interface{}
// @Failure      500  {object}  map[string]interface{}
// @Security     BearerAuth
// @Router       /api/v1/partner/categories [post]
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
// @Summary      Update a menu category
// @Description  Updates an existing menu category with ownership verification
// @Tags         Partners
// @Accept       json
// @Produce      json
// @Param        id    path      string                  true  "Category ID"
// @Param        body  body      map[string]interface{}  true  "Category fields to update"
// @Success      200  {object}  map[string]interface{}
// @Failure      400  {object}  map[string]interface{}
// @Failure      403  {object}  map[string]interface{}
// @Failure      404  {object}  map[string]interface{}
// @Failure      500  {object}  map[string]interface{}
// @Security     BearerAuth
// @Router       /api/v1/partner/categories/{id} [put]
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
// @Summary      Delete a menu category
// @Description  Deletes a menu category with ownership verification
// @Tags         Partners
// @Accept       json
// @Produce      json
// @Param        id  path      string  true  "Category ID"
// @Success      200  {object}  map[string]interface{}
// @Failure      403  {object}  map[string]interface{}
// @Failure      404  {object}  map[string]interface{}
// @Failure      500  {object}  map[string]interface{}
// @Security     BearerAuth
// @Router       /api/v1/partner/categories/{id} [delete]
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
// @Summary      Get partner performance metrics
// @Description  Returns preparation time, acceptance rate, and cancellation rate for the last 7 days
// @Tags         Partners
// @Accept       json
// @Produce      json
// @Param        period  query     string  false  "Time period"
// @Success      200  {object}  map[string]interface{}
// @Failure      403  {object}  map[string]interface{}
// @Failure      500  {object}  map[string]interface{}
// @Security     BearerAuth
// @Router       /api/v1/partner/performance [get]
func (h *PartnerHandler) Performance(c *gin.Context) {
	_, restID, ok := h.getPartnerRestaurant(c)
	if !ok {
		return
	}

	// 30-second Redis cache. Same rationale as Analytics — sliding-7d metrics
	// don't need sub-minute freshness, but the partner app polls this on every
	// dashboard refresh and each uncached hit is a ListOrders(limit=1000).
	perfCacheKey := "partner_performance:" + restID
	if h.redis != nil {
		if cached, err := h.redis.Get(c.Request.Context(), perfCacheKey); err == nil && cached != "" {
			var payload gin.H
			if jerr := json.Unmarshal([]byte(cached), &payload); jerr == nil {
				utils.Success(c, payload)
				return
			}
		}
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

	perfPayload := gin.H{
		"total_orders":      totalOrders,
		"accepted_orders":   acceptedOrders,
		"cancelled_orders":  cancelledOrders,
		"acceptance_rate":   acceptanceRate,
		"cancellation_rate": cancellationRate,
		"avg_prep_time_min": avgPrepTime,
	}
	if h.redis != nil {
		if encoded, jerr := json.Marshal(perfPayload); jerr == nil {
			_ = h.redis.Set(c.Request.Context(), perfCacheKey, string(encoded), 30*time.Second)
		}
	}
	utils.Success(c, perfPayload)
}

// ListReviews returns reviews for the partner's restaurant, newest first.
// @Summary      List reviews for the partner's restaurant
// @Description  Returns reviews for the restaurant owned by the authenticated partner, ordered newest-first. Fails open to an empty list if the underlying reviews collection has schema/index issues, matching the admin endpoint's defensive behaviour so the partner dashboard never surfaces a 500.
// @Tags         Partners
// @Accept       json
// @Produce      json
// @Param        page      query     int  false  "Page number (1-based)"
// @Param        per_page  query     int  false  "Items per page"
// @Success      200  {object}  map[string]interface{}
// @Failure      403  {object}  map[string]interface{}
// @Security     BearerAuth
// @Router       /api/v1/partner/reviews [get]
func (h *PartnerHandler) ListReviews(c *gin.Context) {
	_, restID, ok := h.getPartnerRestaurant(c)
	if !ok {
		return
	}

	p := models.ParsePagination(c)
	queries := []string{
		appwrite.QueryEqual("restaurant_id", restID),
		appwrite.QueryLimit(p.PerPage),
		appwrite.QueryOffset(p.Offset()),
		// reviews collection has no user-defined created_at attribute — use
		// the Appwrite managed $createdAt system field to avoid a 400.
		appwrite.QueryOrderDesc("$createdAt"),
	}

	result, err := h.appwrite.ListReviewsByQuery(queries)
	if err != nil {
		// Fail-open: if the reviews collection is missing an index on
		// restaurant_id the partner dashboard must still render.
		log.Printf("[PartnerHandler.ListReviews] Appwrite error for restaurant %s: %v", restID, err)
		utils.Paginated(c, []map[string]interface{}{}, p.Page, p.PerPage, 0)
		return
	}
	utils.Paginated(c, result.Documents, p.Page, p.PerPage, result.Total)
}

// UpdateRestaurant updates restaurant metadata (e.g. image URL)
// @Summary      Update restaurant
// @Description  Updates restaurant fields such as restaurant_image_url
// @Tags         Partners
// @Accept       json
// @Produce      json
// @Param        body  body  object  true  "Fields to update"
// @Success      200  {object}  map[string]interface{}
// @Failure      400  {object}  map[string]interface{}
// @Failure      403  {object}  map[string]interface{}
// @Failure      500  {object}  map[string]interface{}
// @Security     BearerAuth
// @Router       /api/v1/partner/restaurant [put]
func (h *PartnerHandler) UpdateRestaurant(c *gin.Context) {
	_, restID, ok := h.getPartnerRestaurant(c)
	if !ok {
		return
	}

	var req struct {
		RestaurantImageURL string `json:"restaurant_image_url"`
		Name               string `json:"name"`
		Description        string `json:"description"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}

	updateData := map[string]interface{}{}
	if req.RestaurantImageURL != "" {
		updateData["cover_image_url"] = req.RestaurantImageURL
	}
	if req.Name != "" {
		updateData["name"] = req.Name
	}
	if req.Description != "" {
		updateData["description"] = req.Description
	}

	if len(updateData) == 0 {
		utils.BadRequest(c, "No fields to update")
		return
	}

	updated, err := h.appwrite.UpdateRestaurant(restID, updateData)
	if err != nil {
		utils.InternalError(c, "Failed to update restaurant")
		return
	}
	utils.Success(c, updated)
}

func boolToStatus(b bool) string {
	if b {
		return "online"
	}
	return "offline"
}

// ─── Bank Details & Payouts ───

// GetBankDetails returns the partner's saved bank details and available balance.
// @Summary      Get partner bank details
// @Description  Returns saved bank/UPI details and available earnings balance for the authenticated restaurant partner
// @Tags         Partners
// @Produce      json
// @Success      200  {object}  map[string]interface{}
// @Failure      403  {object}  map[string]interface{}
// @Security     BearerAuth
// @Router       /api/v1/partner/bank-details [get]
func (h *PartnerHandler) GetBankDetails(c *gin.Context) {
	restaurant, _, ok := h.getPartnerRestaurant(c)
	if !ok {
		return
	}
	utils.Success(c, gin.H{
		"bank_account_id":     stringOr(restaurant, "bank_account_id"),
		"bank_account_holder": stringOr(restaurant, "bank_account_holder"),
		"ifsc":                stringOr(restaurant, "ifsc"),
		"upi_id":              stringOr(restaurant, "upi_id"),
		"total_earnings":      getFloat(restaurant, "total_earnings"),
	})
}

// UpdateBankDetails updates the partner's bank account / UPI details.
// @Summary      Update partner bank details
// @Description  Updates bank account or UPI details for the authenticated restaurant partner. IFSC must match Indian bank format.
// @Tags         Partners
// @Accept       json
// @Produce      json
// @Param        body  body  models.UpdatePartnerBankRequest  true  "Bank details payload"
// @Success      200  {object}  map[string]interface{}
// @Failure      400  {object}  map[string]interface{}
// @Failure      403  {object}  map[string]interface{}
// @Failure      500  {object}  map[string]interface{}
// @Security     BearerAuth
// @Router       /api/v1/partner/bank-details [put]
func (h *PartnerHandler) UpdateBankDetails(c *gin.Context) {
	_, restID, ok := h.getPartnerRestaurant(c)
	if !ok {
		return
	}

	var req models.UpdatePartnerBankRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}

	update := map[string]interface{}{}
	if req.BankAccountID != "" {
		if len(req.BankAccountID) < 9 {
			utils.BadRequest(c, "Account number must be at least 9 digits")
			return
		}
		update["bank_account_id"] = req.BankAccountID
	}
	if req.BankAccountHolder != "" {
		update["bank_account_holder"] = req.BankAccountHolder
	}
	if req.IFSC != "" {
		ifsc := strings.ToUpper(strings.TrimSpace(req.IFSC))
		if !isValidIFSC(ifsc) {
			utils.BadRequest(c, "Enter a valid IFSC code (e.g. SBIN0001234)")
			return
		}
		update["ifsc"] = ifsc
	}
	if req.UpiID != "" {
		upi := strings.TrimSpace(req.UpiID)
		if !upiVPARegex.MatchString(upi) {
			utils.BadRequest(c, "Enter a valid UPI ID (e.g. name@upi)")
			return
		}
		update["upi_id"] = upi
	}

	if len(update) == 0 {
		utils.BadRequest(c, "No fields to update")
		return
	}

	updated, err := h.appwrite.UpdateRestaurant(restID, update)
	if err != nil {
		utils.InternalError(c, "Failed to save bank details")
		return
	}
	// Return a clean shape consistent with GetBankDetails
	utils.Success(c, gin.H{
		"bank_account_id":     stringOr(updated, "bank_account_id"),
		"bank_account_holder": stringOr(updated, "bank_account_holder"),
		"ifsc":                stringOr(updated, "ifsc"),
		"upi_id":              stringOr(updated, "upi_id"),
		"total_earnings":      getFloat(updated, "total_earnings"),
	})
}

// ListPayouts returns the partner's payout history.
// @Summary      List partner payouts
// @Description  Returns paginated payout history for the authenticated restaurant partner
// @Tags         Partners
// @Produce      json
// @Param        page     query  int  false  "Page number"     default(1)
// @Param        per_page query  int  false  "Items per page"  default(20)
// @Success      200  {object}  map[string]interface{}
// @Failure      403  {object}  map[string]interface{}
// @Failure      500  {object}  map[string]interface{}
// @Security     BearerAuth
// @Router       /api/v1/partner/payouts [get]
func (h *PartnerHandler) ListPayouts(c *gin.Context) {
	_, restID, ok := h.getPartnerRestaurant(c)
	if !ok {
		return
	}
	pg := models.ParsePagination(c)

	queries := []string{
		appwrite.QueryEqual("partner_id", restID),
		appwrite.QueryOrderDesc("$createdAt"),
		appwrite.QueryLimit(pg.PerPage),
		appwrite.QueryOffset(pg.Offset()),
	}

	result, err := h.appwrite.ListPayouts(queries)
	if err != nil {
		utils.InternalError(c, "Failed to fetch payouts")
		return
	}
	utils.Paginated(c, result.Documents, pg.Page, pg.PerPage, result.Total)
}

// RequestPayout creates a new payout request for the partner.
// @Summary      Request a partner payout
// @Description  Creates a new payout request for the restaurant partner. Minimum ₹100, one pending/processing at a time, requires saved bank or UPI details.
// @Tags         Partners
// @Accept       json
// @Produce      json
// @Param        request  body  models.RequestPayoutRequest  true  "Payout amount and method"
// @Success      201  {object}  map[string]interface{}
// @Failure      400  {object}  map[string]interface{}
// @Failure      403  {object}  map[string]interface{}
// @Failure      500  {object}  map[string]interface{}
// @Security     BearerAuth
// @Router       /api/v1/partner/payouts/request [post]
func (h *PartnerHandler) RequestPayout(c *gin.Context) {
	userID := middleware.GetUserID(c)
	var req models.RequestPayoutRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Amount (>0) and method (bank_transfer|upi) are required")
		return
	}

	restaurant, restID, ok := h.getPartnerRestaurant(c)
	if !ok {
		return
	}

	// Minimum payout
	if req.Amount < 100 {
		utils.BadRequest(c, "Minimum payout amount is ₹100")
		return
	}

	// Required account/UPI info for the chosen method
	switch req.Method {
	case "bank_transfer":
		if stringOr(restaurant, "bank_account_id") == "" ||
			stringOr(restaurant, "ifsc") == "" ||
			stringOr(restaurant, "bank_account_holder") == "" {
			utils.BadRequest(c, "Add bank account holder, number, and IFSC before requesting a bank payout")
			return
		}
	case "upi":
		if stringOr(restaurant, "upi_id") == "" {
			utils.BadRequest(c, "Add a UPI ID before requesting a UPI payout")
			return
		}
	default:
		utils.BadRequest(c, "Method must be bank_transfer or upi")
		return
	}

	// Acquire per-partner distributed lock to prevent concurrent payout double-spend
	lockKey := fmt.Sprintf("payout_lock:partner:%s", restID)
	ctx := context.Background()
	locked, err := h.redis.SetNX(ctx, lockKey, "1", 15*time.Second)
	if err != nil || !locked {
		utils.BadRequest(c, "A payout is already being processed. Please try again.")
		return
	}
	defer h.redis.Del(ctx, lockKey)

	// Re-read balance inside the lock to prevent TOCTOU race
	freshRestaurant, freshRestID, ok := h.getPartnerRestaurant(c)
	if !ok {
		return
	}
	_ = freshRestID

	// Sufficient balance
	totalEarnings := getFloat(freshRestaurant, "total_earnings")
	if req.Amount > totalEarnings {
		utils.BadRequest(c, "Insufficient earnings balance")
		return
	}

	// One pending/processing at a time
	pendingQueries := []string{
		appwrite.QueryEqual("partner_id", restID),
		appwrite.QueryEqual("status", models.PayoutStatusPending),
		appwrite.QueryLimit(1),
	}
	if pending, _ := h.appwrite.ListPayouts(pendingQueries); pending != nil && pending.Total > 0 {
		utils.BadRequest(c, "You already have a pending payout request")
		return
	}
	processingQueries := []string{
		appwrite.QueryEqual("partner_id", restID),
		appwrite.QueryEqual("status", models.PayoutStatusProcessing),
		appwrite.QueryLimit(1),
	}
	if processing, _ := h.appwrite.ListPayouts(processingQueries); processing != nil && processing.Total > 0 {
		utils.BadRequest(c, "A payout is already being processed")
		return
	}

	payout, err := h.appwrite.CreatePayout("unique()", map[string]interface{}{
		"partner_id": restID,
		"user_id":    userID,
		"amount":     req.Amount,
		"status":     models.PayoutStatusPending,
		"method":     req.Method,
		"reference":  "",
		"note":       "",
		"created_at": time.Now().Format(time.RFC3339),
		"updated_at": time.Now().Format(time.RFC3339),
	})
	if err != nil {
		utils.InternalError(c, "Failed to create payout request")
		return
	}

	// Deduct from available balance — if this fails, roll back the payout document
	newBalance := totalEarnings - req.Amount
	if _, balErr := h.appwrite.UpdateRestaurant(restID, map[string]interface{}{
		"total_earnings": newBalance,
	}); balErr != nil {
		payoutID, _ := payout["$id"].(string)
		if payoutID != "" {
			_ = h.appwrite.DeletePayout(payoutID)
		}
		utils.InternalError(c, "Failed to deduct balance; payout cancelled")
		return
	}

	// Notify partner
	_, _ = h.appwrite.CreateNotification("unique()", map[string]interface{}{
		"user_id": userID,
		"title":   "Payout Requested",
		"body":    fmt.Sprintf("Your payout of ₹%.0f is being processed", req.Amount),
		"type":    "payout",
		"is_read": false,
	})

	utils.Created(c, payout)
}

// stringOr reads a string field from a map-backed Appwrite document.
func stringOr(doc map[string]interface{}, key string) string {
	if v, ok := doc[key].(string); ok {
		return v
	}
	return ""
}

// isValidIFSC returns true if s matches Indian IFSC format (4 letters + 0 + 6 alphanumeric).
func isValidIFSC(s string) bool {
	if len(s) != 11 {
		return false
	}
	for i, ch := range s {
		switch {
		case i < 4:
			if !(ch >= 'A' && ch <= 'Z') {
				return false
			}
		case i == 4:
			if ch != '0' {
				return false
			}
		default:
			if !((ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9')) {
				return false
			}
		}
	}
	return true
}
