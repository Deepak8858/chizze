package handlers

import (
	"context"
	"time"

	"github.com/chizze/backend/internal/middleware"
	"github.com/chizze/backend/internal/models"
	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/pkg/appwrite"
	redispkg "github.com/chizze/backend/pkg/redis"
	"github.com/chizze/backend/pkg/utils"
	"github.com/gin-gonic/gin"
)

// DeliveryHandler handles delivery partner endpoints
type DeliveryHandler struct {
	appwrite *services.AppwriteService
	geo      *services.GeoService
	redis    *redispkg.Client
}

// NewDeliveryHandler creates a delivery handler
func NewDeliveryHandler(aw *services.AppwriteService, geo *services.GeoService, redis *redispkg.Client) *DeliveryHandler {
	return &DeliveryHandler{appwrite: aw, geo: geo, redis: redis}
}

// ToggleOnline sets delivery partner online/offline
// PUT /api/v1/delivery/status
func (h *DeliveryHandler) ToggleOnline(c *gin.Context) {
	userID := middleware.GetUserID(c)
	var req struct {
		IsOnline bool `json:"is_online"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Invalid request")
		return
	}

	partnerResult, err := h.appwrite.GetDeliveryPartner(userID)
	if err != nil || partnerResult.Total == 0 {
		utils.NotFound(c, "Delivery partner profile not found")
		return
	}

	partnerID, _ := partnerResult.Documents[0]["$id"].(string)
	updated, err := h.appwrite.UpdateDeliveryPartner(partnerID, map[string]interface{}{
		"is_online": req.IsOnline,
	})
	if err != nil {
		utils.InternalError(c, "Failed to update status")
		return
	}
	utils.Success(c, updated)
}

// UpdateLocation pushes delivery partner location with heading/speed
// PUT /api/v1/delivery/location
func (h *DeliveryHandler) UpdateLocation(c *gin.Context) {
	userID := middleware.GetUserID(c)
	var req struct {
		Latitude  float64 `json:"latitude" binding:"required"`
		Longitude float64 `json:"longitude" binding:"required"`
		Heading   float64 `json:"heading"`
		Speed     float64 `json:"speed"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Latitude and longitude are required")
		return
	}

	partnerResult, err := h.appwrite.GetDeliveryPartner(userID)
	if err != nil || partnerResult.Total == 0 {
		utils.NotFound(c, "Delivery partner not found")
		return
	}

	partnerID, _ := partnerResult.Documents[0]["$id"].(string)

	// Update partner's current location
	_, err = h.appwrite.UpdateDeliveryPartner(partnerID, map[string]interface{}{
		"current_latitude":  req.Latitude,
		"current_longitude": req.Longitude,
		"heading":           req.Heading,
		"speed":             req.Speed,
		"last_location_at":  time.Now().Format(time.RFC3339),
	})
	if err != nil {
		utils.InternalError(c, "Failed to update location")
		return
	}

	// Also store in rider_locations for tracking history
	_, _ = h.appwrite.CreateDeliveryLocation("unique()", map[string]interface{}{
		"partner_id": userID,
		"latitude":   req.Latitude,
		"longitude":  req.Longitude,
		"heading":    req.Heading,
		"speed":      req.Speed,
		"timestamp":  time.Now().Format(time.RFC3339),
	})

	utils.Success(c, gin.H{"message": "Location updated"})
}

// AcceptOrder assigns delivery partner to an order (sets partner, keeps status as ready)
// PUT /api/v1/delivery/orders/:id/accept
func (h *DeliveryHandler) AcceptOrder(c *gin.Context) {
	orderID := c.Param("id")
	userID := middleware.GetUserID(c)

	// Distributed lock to prevent two partners accepting simultaneously
	if h.redis != nil {
		ctx := context.Background()
		lockKey := "delivery_lock:" + orderID
		acquired, err := h.redis.SetNX(ctx, lockKey, userID, 30*time.Second)
		if err != nil || !acquired {
			utils.BadRequest(c, "Order is being accepted by another partner")
			return
		}
		defer h.redis.Del(ctx, lockKey)
	}

	// Verify order exists and is in ready status
	order, err := h.appwrite.GetOrder(orderID)
	if err != nil {
		utils.NotFound(c, "Order not found")
		return
	}

	currentStatus, _ := order["status"].(string)
	if currentStatus != models.OrderStatusReady {
		utils.BadRequest(c, "Order is not available for pickup (status: "+currentStatus+")")
		return
	}

	// Check if already assigned
	existingPartner, _ := order["delivery_partner_id"].(string)
	if existingPartner != "" {
		utils.BadRequest(c, "Order already assigned to a delivery partner")
		return
	}

	// Verify partner is online
	partnerResult, err := h.appwrite.GetDeliveryPartner(userID)
	if err != nil || partnerResult.Total == 0 {
		utils.Forbidden(c, "Delivery partner profile not found")
		return
	}
	isOnline, _ := partnerResult.Documents[0]["is_online"].(bool)
	if !isOnline {
		utils.BadRequest(c, "You must be online to accept orders")
		return
	}

	// Assign partner to order without changing status
	_, err = h.appwrite.UpdateOrder(orderID, map[string]interface{}{
		"delivery_partner_id": userID,
		"accepted_at":         time.Now().Format(time.RFC3339),
	})
	if err != nil {
		utils.InternalError(c, "Failed to accept order")
		return
	}
	utils.Success(c, gin.H{"message": "Order accepted", "order_id": orderID})
}

// getDeliveryPartnerProfile looks up the delivery partner document for the current user
func (h *DeliveryHandler) getDeliveryPartnerProfile(c *gin.Context) (map[string]interface{}, string, bool) {
	userID := middleware.GetUserID(c)
	result, err := h.appwrite.GetDeliveryPartner(userID)
	if err != nil || result == nil || len(result.Documents) == 0 {
		utils.NotFound(c, "Delivery partner profile not found")
		return nil, "", false
	}
	partner := result.Documents[0]
	partnerID, _ := partner["$id"].(string)
	return partner, partnerID, true
}

// ActiveOrders returns orders assigned to or available for this delivery partner
// GET /api/v1/delivery/orders
func (h *DeliveryHandler) ActiveOrders(c *gin.Context) {
	userID := middleware.GetUserID(c)
	pg := models.ParsePagination(c)

	mode := c.DefaultQuery("mode", "assigned") // assigned or available

	var queries []string
	if mode == "available" {
		// Show ready orders without a delivery partner
		queries = []string{
			appwrite.QueryEqual("status", models.OrderStatusReady),
			appwrite.QueryEqual("delivery_partner_id", ""),
			appwrite.QueryOrderDesc("placed_at"),
			appwrite.QueryLimit(pg.PerPage),
			appwrite.QueryOffset(pg.Offset()),
		}
	} else {
		// Show orders assigned to this partner
		queries = []string{
			appwrite.QueryEqual("delivery_partner_id", userID),
			appwrite.QueryOrderDesc("placed_at"),
			appwrite.QueryLimit(pg.PerPage),
			appwrite.QueryOffset(pg.Offset()),
		}
	}

	result, err := h.appwrite.ListOrders(queries)
	if err != nil {
		utils.InternalError(c, "Failed to fetch orders")
		return
	}
	utils.Paginated(c, result.Documents, pg.Page, pg.PerPage, result.Total)
}

// Dashboard returns delivery partner dashboard metrics
// GET /api/v1/delivery/dashboard
func (h *DeliveryHandler) Dashboard(c *gin.Context) {
	partner, _, ok := h.getDeliveryPartnerProfile(c)
	if !ok {
		return
	}
	userID := middleware.GetUserID(c)

	// Get today's completed/active orders for this partner
	now := time.Now()
	todayStart := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	todayStartStr := todayStart.Format(time.RFC3339)

	queries := []string{
		appwrite.QueryEqual("delivery_partner_id", userID),
		appwrite.QueryGreaterThanEqual("placed_at", todayStartStr),
		appwrite.QueryLimit(500),
	}

	orderResult, err := h.appwrite.ListOrders(queries)
	if err != nil {
		utils.InternalError(c, "Failed to fetch orders")
		return
	}

	// Calculate today's metrics
	todayEarnings := 0.0
	todayDeliveries := 0
	todayDistanceKm := 0.0
	activeDeliveryOrder := map[string]interface{}(nil)

	for _, order := range orderResult.Documents {
		status, _ := order["status"].(string)
		switch status {
		case models.OrderStatusDelivered:
			todayDeliveries++
			// Delivery fee + tip = partner earnings
			todayEarnings += getFloat(order, "delivery_fee") + getFloat(order, "tip")
			todayDistanceKm += getFloat(order, "distance_km")
		case models.OrderStatusPickedUp, models.OrderStatusOutForDelivery:
			// Currently delivering this order
			activeDeliveryOrder = order
		}
	}

	// Weekly progress (last 7 days)
	weekStart := now.AddDate(0, 0, -7).Format(time.RFC3339)
	weekQueries := []string{
		appwrite.QueryEqual("delivery_partner_id", userID),
		appwrite.QueryGreaterThanEqual("placed_at", weekStart),
		appwrite.QueryEqual("status", models.OrderStatusDelivered),
		appwrite.QueryLimit(1000),
	}
	weekResult, _ := h.appwrite.ListOrders(weekQueries)
	weeklyCompleted := 0
	if weekResult != nil {
		weeklyCompleted = len(weekResult.Documents)
	}

	isOnline, _ := partner["is_online"].(bool)
	rating, _ := partner["rating"].(float64)
	totalDeliveries := getFloat(partner, "total_deliveries")
	totalEarnings := getFloat(partner, "total_earnings")
	vehicleType, _ := partner["vehicle_type"].(string)
	vehicleNumber, _ := partner["vehicle_number"].(string)

	resp := gin.H{
		"is_online":         isOnline,
		"rating":            rating,
		"total_deliveries":  int(totalDeliveries),
		"total_earnings":    totalEarnings,
		"vehicle_type":      vehicleType,
		"vehicle_number":    vehicleNumber,
		"today_earnings":    todayEarnings,
		"today_deliveries":  todayDeliveries,
		"today_distance_km": todayDistanceKm,
		"weekly_goal":       50,
		"weekly_completed":  weeklyCompleted,
	}

	if activeDeliveryOrder != nil {
		resp["active_order"] = activeDeliveryOrder
	}

	utils.Success(c, resp)
}

// Earnings returns earnings breakdown for the delivery partner
// GET /api/v1/delivery/earnings?period=week (day|week|month)
func (h *DeliveryHandler) Earnings(c *gin.Context) {
	userID := middleware.GetUserID(c)

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

	// Fetch delivered orders in the period
	queries := []string{
		appwrite.QueryEqual("delivery_partner_id", userID),
		appwrite.QueryGreaterThanEqual("placed_at", fromDateStr),
		appwrite.QueryEqual("status", models.OrderStatusDelivered),
		appwrite.QueryOrderDesc("placed_at"),
		appwrite.QueryLimit(1000),
	}

	result, err := h.appwrite.ListOrders(queries)
	if err != nil {
		utils.InternalError(c, "Failed to fetch earnings data")
		return
	}

	// Aggregate
	totalEarnings := 0.0
	totalTips := 0.0
	dailyMap := make(map[string]float64) // "Mon" => amount
	dailyTrips := make(map[string]int)

	recentTrips := make([]gin.H, 0, 20)

	for _, order := range result.Documents {
		fee := getFloat(order, "delivery_fee")
		tip := getFloat(order, "tip")
		distance := getFloat(order, "distance_km")
		tripEarning := fee + tip
		totalEarnings += tripEarning
		totalTips += tip

		// Daily aggregation
		placedAtStr, _ := order["placed_at"].(string)
		if t, err := time.Parse(time.RFC3339, placedAtStr); err == nil {
			dayKey := t.Weekday().String()[:3]
			dailyMap[dayKey] += tripEarning
			dailyTrips[dayKey]++
		}

		// Build recent trips (up to 20)
		if len(recentTrips) < 20 {
			orderNumber, _ := order["order_number"].(string)
			restID, _ := order["restaurant_id"].(string)
			ordID, _ := order["$id"].(string)

			// Calculate duration from accepted_at to delivered_at
			durationMin := 0
			acceptedStr, _ := order["accepted_at"].(string)
			deliveredStr, _ := order["delivered_at"].(string)
			if acceptedStr != "" && deliveredStr != "" {
				a, e1 := time.Parse(time.RFC3339, acceptedStr)
				d, e2 := time.Parse(time.RFC3339, deliveredStr)
				if e1 == nil && e2 == nil {
					durationMin = int(d.Sub(a).Minutes())
				}
			}

			recentTrips = append(recentTrips, gin.H{
				"order_id":        ordID,
				"order_number":    orderNumber,
				"restaurant_id":   restID,
				"amount":          tripEarning,
				"tip":             tip,
				"distance_km":     distance,
				"duration_min":    durationMin,
				"completed_at":    deliveredStr,
			})
		}
	}

	// Build weekly data
	weekdays := []string{"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"}
	weeklyData := make([]gin.H, 0, 7)
	for _, day := range weekdays {
		weeklyData = append(weeklyData, gin.H{
			"day":    day,
			"amount": dailyMap[day],
			"trips":  dailyTrips[day],
		})
	}

	// Monthly total (always fetch full month regardless of period param)
	monthStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, now.Location()).Format(time.RFC3339)
	monthQueries := []string{
		appwrite.QueryEqual("delivery_partner_id", userID),
		appwrite.QueryGreaterThanEqual("placed_at", monthStart),
		appwrite.QueryEqual("status", models.OrderStatusDelivered),
		appwrite.QueryLimit(1000),
	}
	monthlyTotal := 0.0
	if monthResult, mErr := h.appwrite.ListOrders(monthQueries); mErr == nil && monthResult != nil {
		for _, order := range monthResult.Documents {
			monthlyTotal += getFloat(order, "delivery_fee") + getFloat(order, "tip")
		}
	}

	utils.Success(c, gin.H{
		"period":         period,
		"weekly_total":   totalEarnings,
		"monthly_total":  monthlyTotal,
		"total_tips":     totalTips,
		"total_trips":    len(result.Documents),
		"weekly_data":    weeklyData,
		"recent_trips":   recentTrips,
	})
}

// Performance returns delivery performance metrics for the partner
// GET /api/v1/delivery/performance
func (h *DeliveryHandler) Performance(c *gin.Context) {
	_, _, ok := h.getDeliveryPartnerProfile(c)
	if !ok {
		return
	}
	userID := middleware.GetUserID(c)

	// Get last 7 days of orders assigned to this partner
	fromDate := time.Now().AddDate(0, 0, -7).Format(time.RFC3339)
	queries := []string{
		appwrite.QueryEqual("delivery_partner_id", userID),
		appwrite.QueryGreaterThanEqual("placed_at", fromDate),
		appwrite.QueryLimit(1000),
	}

	result, err := h.appwrite.ListOrders(queries)
	if err != nil {
		utils.InternalError(c, "Failed to fetch performance data")
		return
	}

	totalOrders := len(result.Documents)
	deliveredOrders := 0
	cancelledOrders := 0
	totalDeliveryTimeMin := 0.0
	deliveryTimeCount := 0

	// Track daily delivery counts for trend
	dailyDelivered := make(map[string]int)

	for _, order := range result.Documents {
		status, _ := order["status"].(string)
		switch status {
		case models.OrderStatusDelivered:
			deliveredOrders++
			// Calculate delivery time (accepted_at → delivered_at)
			acceptedStr, _ := order["accepted_at"].(string)
			deliveredStr, _ := order["delivered_at"].(string)
			if acceptedStr != "" && deliveredStr != "" {
				a, e1 := time.Parse(time.RFC3339, acceptedStr)
				d, e2 := time.Parse(time.RFC3339, deliveredStr)
				if e1 == nil && e2 == nil {
					dt := d.Sub(a).Minutes()
					if dt > 0 && dt < 180 { // sanity: < 3 hours
						totalDeliveryTimeMin += dt
						deliveryTimeCount++
					}
				}
			}
			// Daily trend
			placedAtStr, _ := order["placed_at"].(string)
			if t, err := time.Parse(time.RFC3339, placedAtStr); err == nil {
				dayKey := t.Weekday().String()[:3]
				dailyDelivered[dayKey]++
			}
		case models.OrderStatusCancelled:
			cancelledOrders++
		}
	}

	completionRate := 0.0
	cancellationRate := 0.0
	avgDeliveryTimeMin := 0.0
	if totalOrders > 0 {
		completionRate = float64(deliveredOrders) / float64(totalOrders) * 100
		cancellationRate = float64(cancelledOrders) / float64(totalOrders) * 100
	}
	if deliveryTimeCount > 0 {
		avgDeliveryTimeMin = totalDeliveryTimeMin / float64(deliveryTimeCount)
	}

	// Build daily trend
	weekdays := []string{"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"}
	dailyTrend := make([]gin.H, 0, 7)
	for _, day := range weekdays {
		dailyTrend = append(dailyTrend, gin.H{
			"day":        day,
			"deliveries": dailyDelivered[day],
		})
	}

	// Sort daily trend by delivery count to find peak day
	peakDay := ""
	peakCount := 0
	for _, day := range weekdays {
		if dailyDelivered[day] > peakCount {
			peakCount = dailyDelivered[day]
			peakDay = day
		}
	}

	utils.Success(c, gin.H{
		"total_orders":         totalOrders,
		"delivered_orders":     deliveredOrders,
		"cancelled_orders":     cancelledOrders,
		"completion_rate":      completionRate,
		"cancellation_rate":    cancellationRate,
		"avg_delivery_time_min": avgDeliveryTimeMin,
		"daily_trend":          dailyTrend,
		"peak_day":             peakDay,
	})
}
