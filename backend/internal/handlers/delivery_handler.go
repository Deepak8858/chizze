package handlers

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/chizze/backend/internal/middleware"
	"github.com/chizze/backend/internal/models"
	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/internal/websocket"
	"github.com/chizze/backend/pkg/appwrite"
	redispkg "github.com/chizze/backend/pkg/redis"
	"github.com/chizze/backend/pkg/utils"
	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
)

// DeliveryHandler handles delivery partner endpoints
type DeliveryHandler struct {
	appwrite    *services.AppwriteService
	geo         *services.GeoService
	redis       *redispkg.Client
	broadcaster *websocket.EventBroadcaster
}

// NewDeliveryHandler creates a delivery handler
func NewDeliveryHandler(aw *services.AppwriteService, geo *services.GeoService, redis *redispkg.Client, broadcaster ...*websocket.EventBroadcaster) *DeliveryHandler {
	h := &DeliveryHandler{appwrite: aw, geo: geo, redis: redis}
	if len(broadcaster) > 0 {
		h.broadcaster = broadcaster[0]
	}
	return h
}

// ToggleOnline sets delivery partner online/offline
// @Summary Toggle online status
// @Description Sets delivery partner online or offline and updates Redis geo set accordingly
// @Tags Delivery
// @Accept json
// @Produce json
// @Param request body object{is_online=bool} true "Online status"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]string
// @Failure 401 {object} map[string]string
// @Failure 404 {object} map[string]string
// @Failure 500 {object} map[string]string
// @Security BearerAuth
// @Router /api/v1/delivery/status [put]
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

	// Update Redis geo set: add location when online, remove when offline
	if h.redis != nil {
		geoCtx := context.Background()
		if req.IsOnline {
			// Re-add with last known location (will be overwritten by UpdateLocation)
			lat, _ := partnerResult.Documents[0]["current_latitude"].(float64)
			lng, _ := partnerResult.Documents[0]["current_longitude"].(float64)
			if lat != 0 && lng != 0 {
				h.redis.GeoAdd(geoCtx, "rider_locations", &redis.GeoLocation{
					Name:      userID,
					Longitude: lng,
					Latitude:  lat,
				})
			}
		} else {
			// Remove rider from geo set when going offline
			h.redis.ZRem(geoCtx, "rider_locations", userID)
		}
	}

	utils.Success(c, updated)
}

// UpdateLocation pushes delivery partner location with heading/speed
// @Summary Update delivery partner location
// @Description Pushes the delivery partner's current GPS location, heading, and speed; broadcasts to customers tracking active deliveries
// @Tags Delivery
// @Accept json
// @Produce json
// @Param request body object{latitude=number,longitude=number,heading=number,speed=number} true "Location data"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]string
// @Failure 401 {object} map[string]string
// @Failure 404 {object} map[string]string
// @Failure 500 {object} map[string]string
// @Security BearerAuth
// @Router /api/v1/delivery/location [put]
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

	// Store rider position in Redis geo set for proximity matching
	if h.redis != nil {
		geoCtx := context.Background()
		_, geoErr := h.redis.GeoAdd(geoCtx, "rider_locations", &redis.GeoLocation{
			Name:      userID,
			Longitude: req.Longitude,
			Latitude:  req.Latitude,
		})
		if geoErr != nil {
			log.Printf("[delivery] GeoAdd rider_locations failed for %s: %v", userID, geoErr)
		}
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

	// Broadcast live location to customers tracking this rider's deliveries
	if h.broadcaster != nil {
		// Find active orders for this rider and broadcast location to each customer
		activeOrders, err := h.appwrite.ListOrders([]string{
			appwrite.QueryEqual("delivery_partner_id", userID),
			appwrite.QueryEqual("status", "out_for_delivery"),
		})
		if err == nil && activeOrders != nil {
			for _, o := range activeOrders.Documents {
				custID, _ := o["user_id"].(string)
				oID, _ := o["$id"].(string)
				if custID != "" {
					h.broadcaster.BroadcastDeliveryLocation(custID, oID, req.Latitude, req.Longitude, req.Heading)
				}
			}
		}
	}

	utils.Success(c, gin.H{"message": "Location updated"})
}

// AcceptOrder assigns delivery partner to an order (sets partner, keeps status as ready)
// @Summary Accept a delivery order
// @Description Assigns the delivery partner to an order using a distributed lock to prevent double-acceptance
// @Tags Delivery
// @Accept json
// @Produce json
// @Param id path string true "Order ID"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]string
// @Failure 401 {object} map[string]string
// @Failure 403 {object} map[string]string
// @Failure 404 {object} map[string]string
// @Failure 500 {object} map[string]string
// @Security BearerAuth
// @Router /api/v1/delivery/orders/{id}/accept [put]
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

	// Notify customer that a delivery partner accepted their order
	customerID, _ := order["user_id"].(string)
	orderNumber, _ := order["order_number"].(string)
	if customerID != "" {
		_, _ = h.appwrite.CreateNotification("unique()", map[string]interface{}{
			"user_id":    customerID,
			"title":      "Delivery Partner Assigned",
			"body":       "A delivery partner has been assigned to your order " + orderNumber,
			"type":       "delivery_update",
			"data":       map[string]interface{}{"order_id": orderID},
			"is_read":    false,
			"created_at": time.Now().Format(time.RFC3339),
		})
		// Broadcast via WebSocket for live tracking
		if h.broadcaster != nil {
			h.broadcaster.BroadcastOrderUpdate(customerID, orderID, "rider_assigned", "A delivery partner is on the way")
		}
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
// @Summary List active delivery orders
// @Description Returns orders assigned to the partner or available for pickup depending on mode query param
// @Tags Delivery
// @Accept json
// @Produce json
// @Param mode query string false "Filter mode: assigned or available" default(assigned)
// @Param page query int false "Page number" default(1)
// @Param per_page query int false "Items per page" default(20)
// @Success 200 {object} map[string]interface{}
// @Failure 401 {object} map[string]string
// @Failure 500 {object} map[string]string
// @Security BearerAuth
// @Router /api/v1/delivery/orders [get]
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
// @Summary Get delivery dashboard
// @Description Returns today's earnings, deliveries, distance, weekly progress, and active order info
// @Tags Delivery
// @Accept json
// @Produce json
// @Success 200 {object} map[string]interface{}
// @Failure 401 {object} map[string]string
// @Failure 404 {object} map[string]string
// @Failure 500 {object} map[string]string
// @Security BearerAuth
// @Router /api/v1/delivery/dashboard [get]
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
// @Summary Get delivery earnings
// @Description Returns earnings breakdown with weekly data, recent trips, and monthly totals
// @Tags Delivery
// @Accept json
// @Produce json
// @Param period query string false "Time period: day, week, or month" default(week)
// @Success 200 {object} map[string]interface{}
// @Failure 401 {object} map[string]string
// @Failure 500 {object} map[string]string
// @Security BearerAuth
// @Router /api/v1/delivery/earnings [get]
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
// @Summary Get delivery performance
// @Description Returns completion rate, cancellation rate, avg delivery time, and daily trend for the last 7 days
// @Tags Delivery
// @Accept json
// @Produce json
// @Param period query string false "Time period" default(week)
// @Success 200 {object} map[string]interface{}
// @Failure 401 {object} map[string]string
// @Failure 404 {object} map[string]string
// @Failure 500 {object} map[string]string
// @Security BearerAuth
// @Router /api/v1/delivery/performance [get]
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

// GetProfile returns the delivery partner's full profile
// @Summary Get delivery partner profile
// @Description Returns the full profile of the authenticated delivery partner
// @Tags Delivery
// @Accept json
// @Produce json
// @Success 200 {object} map[string]interface{}
// @Failure 401 {object} map[string]string
// @Failure 404 {object} map[string]string
// @Security BearerAuth
// @Router /api/v1/delivery/profile [get]
func (h *DeliveryHandler) GetProfile(c *gin.Context) {
	partner, _, ok := h.getDeliveryPartnerProfile(c)
	if !ok {
		return
	}
	utils.Success(c, partner)
}

// UpdateProfile updates delivery partner profile fields (vehicle, bank, etc.)
// @Summary Update delivery partner profile
// @Description Updates delivery partner profile fields such as vehicle type, vehicle number, and bank account
// @Tags Delivery
// @Accept json
// @Produce json
// @Param request body models.UpdateDeliveryProfileRequest true "Profile fields to update"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]string
// @Failure 401 {object} map[string]string
// @Failure 404 {object} map[string]string
// @Failure 500 {object} map[string]string
// @Security BearerAuth
// @Router /api/v1/delivery/profile [put]
func (h *DeliveryHandler) UpdateProfile(c *gin.Context) {
	var req models.UpdateDeliveryProfileRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}

	_, partnerID, ok := h.getDeliveryPartnerProfile(c)
	if !ok {
		return
	}

	updateData := map[string]interface{}{}
	if req.VehicleType != "" {
		updateData["vehicle_type"] = req.VehicleType
	}
	if req.VehicleNumber != "" {
		updateData["vehicle_number"] = req.VehicleNumber
	}
	if req.BankAccountID != "" {
		updateData["bank_account_id"] = req.BankAccountID
	}

	if len(updateData) == 0 {
		utils.BadRequest(c, "No fields to update")
		return
	}

	updated, err := h.appwrite.UpdateDeliveryPartner(partnerID, updateData)
	if err != nil {
		utils.InternalError(c, "Failed to update profile")
		return
	}
	utils.Success(c, updated)
}

// ListPayouts returns the delivery partner's payout history
// @Summary List payouts
// @Description Returns paginated payout history for the authenticated delivery partner
// @Tags Delivery
// @Accept json
// @Produce json
// @Param page query int false "Page number" default(1)
// @Param per_page query int false "Items per page" default(20)
// @Success 200 {object} map[string]interface{}
// @Failure 401 {object} map[string]string
// @Failure 500 {object} map[string]string
// @Security BearerAuth
// @Router /api/v1/delivery/payouts [get]
func (h *DeliveryHandler) ListPayouts(c *gin.Context) {
	userID := middleware.GetUserID(c)
	pg := models.ParsePagination(c)

	queries := []string{
		appwrite.QueryEqual("user_id", userID),
		appwrite.QueryOrderDesc("created_at"),
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

// RequestPayout creates a new payout request for the delivery partner
// @Summary Request a payout
// @Description Creates a new payout request; minimum ₹100, one pending request at a time
// @Tags Delivery
// @Accept json
// @Produce json
// @Param request body models.RequestPayoutRequest true "Payout amount and method"
// @Success 201 {object} map[string]interface{}
// @Failure 400 {object} map[string]string
// @Failure 401 {object} map[string]string
// @Failure 404 {object} map[string]string
// @Failure 500 {object} map[string]string
// @Security BearerAuth
// @Router /api/v1/delivery/payouts/request [post]
func (h *DeliveryHandler) RequestPayout(c *gin.Context) {
	userID := middleware.GetUserID(c)
	var req models.RequestPayoutRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Amount (>0) and method (bank_transfer|upi) are required")
		return
	}

	partner, partnerID, ok := h.getDeliveryPartnerProfile(c)
	if !ok {
		return
	}

	// Validate minimum payout
	if req.Amount < 100 {
		utils.BadRequest(c, "Minimum payout amount is ₹100")
		return
	}

	// Check that partner has sufficient balance
	totalEarnings := getFloat(partner, "total_earnings")
	if req.Amount > totalEarnings {
		utils.BadRequest(c, "Insufficient earnings balance")
		return
	}

	// Check for pending/processing payouts (only one at a time)
	pendingQueries := []string{
		appwrite.QueryEqual("user_id", userID),
		appwrite.QueryEqual("status", models.PayoutStatusPending),
		appwrite.QueryLimit(1),
	}
	if pending, _ := h.appwrite.ListPayouts(pendingQueries); pending != nil && pending.Total > 0 {
		utils.BadRequest(c, "You already have a pending payout request")
		return
	}

	processingQueries := []string{
		appwrite.QueryEqual("user_id", userID),
		appwrite.QueryEqual("status", models.PayoutStatusProcessing),
		appwrite.QueryLimit(1),
	}
	if processing, _ := h.appwrite.ListPayouts(processingQueries); processing != nil && processing.Total > 0 {
		utils.BadRequest(c, "A payout is already being processed")
		return
	}

	// Create payout record
	payout, err := h.appwrite.CreatePayout("unique()", map[string]interface{}{
		"partner_id": partnerID,
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

	// Deduct from partner's total_earnings (available balance)
	newBalance := totalEarnings - req.Amount
	_, _ = h.appwrite.UpdateDeliveryPartner(partnerID, map[string]interface{}{
		"total_earnings": newBalance,
	})

	// Create notification for partner
	_, _ = h.appwrite.CreateNotification("unique()", map[string]interface{}{
		"user_id":    userID,
		"title":      "Payout Requested",
		"body":       "Your payout of ₹" + fmt.Sprintf("%.0f", req.Amount) + " is being processed",
		"type":       "payout",
		"is_read":    false,
		"created_at": time.Now().Format(time.RFC3339),
	})

	utils.Created(c, payout)
}

// RejectOrder rejects/skips an order assignment
// @Summary Reject a delivery order
// @Description Rejects an order assignment and unassigns the delivery partner from the order
// @Tags Delivery
// @Accept json
// @Produce json
// @Param id path string true "Order ID"
// @Success 200 {object} map[string]interface{}
// @Failure 401 {object} map[string]string
// @Failure 403 {object} map[string]string
// @Failure 404 {object} map[string]string
// @Failure 500 {object} map[string]string
// @Security BearerAuth
// @Router /api/v1/delivery/orders/{id}/reject [put]
func (h *DeliveryHandler) RejectOrder(c *gin.Context) {
	orderID := c.Param("id")
	userID := middleware.GetUserID(c)

	// Verify order exists and is assigned to this partner
	order, err := h.appwrite.GetOrder(orderID)
	if err != nil {
		utils.NotFound(c, "Order not found")
		return
	}

	assignedPartner, _ := order["delivery_partner_id"].(string)
	if assignedPartner != userID {
		utils.Forbidden(c, "Order not assigned to you")
		return
	}

	// Unassign partner
	_, err = h.appwrite.UpdateOrder(orderID, map[string]interface{}{
		"delivery_partner_id": "",
		"accepted_at":         "",
	})
	if err != nil {
		utils.InternalError(c, "Failed to reject order")
		return
	}
	utils.Success(c, gin.H{"message": "Order rejected", "order_id": orderID})
}
