package handlers

import (
	"context"
	"fmt"
	"log"
	"strings"
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
	appwrite        *services.AppwriteService
	geo             *services.GeoService
	redis           *redispkg.Client
	broadcaster     *websocket.EventBroadcaster
	matcherCallback func() // called after rejection to instantly re-dispatch
}

// SetMatcherCallback registers a function that is called after a rider rejects
// an order, so the delivery matcher can immediately find the next eligible rider.
func (h *DeliveryHandler) SetMatcherCallback(fn func()) {
	h.matcherCallback = fn
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
	updateFields := map[string]interface{}{
		"is_online": req.IsOnline,
	}
	if req.IsOnline {
		updateFields["login_at"] = time.Now().Format(time.RFC3339)
	}
	updated, err := h.appwrite.UpdateDeliveryPartner(partnerID, updateFields)
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
		log.Printf("[delivery] UpdateLocation failed for partner %s (user %s): %v", partnerID, userID, err)
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

	// Also store in rider_locations for tracking (upsert: update existing or create new)
	locData := map[string]interface{}{
		"rider_id":  userID,
		"latitude":  req.Latitude,
		"longitude": req.Longitude,
		"heading":   req.Heading,
		"speed":     req.Speed,
		"is_online": true,
	}
	existingLocs, locErr := h.appwrite.ListDeliveryLocations([]string{
		appwrite.QueryEqual("rider_id", userID),
		appwrite.QueryLimit(1),
	})
	if locErr == nil && existingLocs != nil && existingLocs.Total > 0 {
		locID, _ := existingLocs.Documents[0]["$id"].(string)
		if _, err := h.appwrite.UpdateDeliveryLocation(locID, locData); err != nil {
			log.Printf("[delivery] UpdateDeliveryLocation failed for rider %s (loc %s): %v", userID, locID, err)
		}
	} else {
		if _, err := h.appwrite.CreateDeliveryLocation("unique()", locData); err != nil {
			log.Printf("[delivery] CreateDeliveryLocation failed for rider %s: %v", userID, err)
		}
	}

	// Broadcast live location to customers tracking this rider's deliveries.
	// Include both picked_up (rider heading to restaurant / just picked up)
	// and out_for_delivery (rider heading to customer) so the customer gets
	// continuous tracking from pickup to delivery.
	if h.broadcaster != nil {
		for _, trackStatus := range []string{models.OrderStatusPickedUp, models.OrderStatusOutForDelivery} {
			activeOrders, err := h.appwrite.ListOrders([]string{
				appwrite.QueryEqual("delivery_partner_id", userID),
				appwrite.QueryEqual("status", trackStatus),
			})
			if err == nil && activeOrders != nil {
				for _, o := range activeOrders.Documents {
					custID, _ := o["customer_id"].(string)
					oID, _ := o["$id"].(string)
					if custID != "" {
						h.broadcaster.BroadcastDeliveryLocation(custID, oID, req.Latitude, req.Longitude, req.Heading)
					}
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

	// Extract partner name and phone from profile, falling back to users collection
	// because delivery_partners collection may not store name/phone directly.
	partnerName, _ := partnerResult.Documents[0]["name"].(string)
	partnerPhone, _ := partnerResult.Documents[0]["phone"].(string)
	if partnerName == "" || partnerPhone == "" {
		if user, uErr := h.appwrite.GetUser(userID); uErr == nil && user != nil {
			if partnerName == "" {
				if n, _ := user["name"].(string); n != "" {
					partnerName = n
				}
			}
			if partnerPhone == "" {
				if p, _ := user["phone"].(string); p != "" {
					partnerPhone = p
				}
			}
		}
	}

	// Assign partner to order with name/phone for enrichment
	updateData := map[string]interface{}{
		"delivery_partner_id":    userID,
		"delivery_partner_name":  partnerName,
		"delivery_partner_phone": partnerPhone,
	}
	_, err = h.appwrite.UpdateOrder(orderID, updateData)
	if err != nil {
		utils.InternalError(c, "Failed to accept order")
		return
	}

	// Clear the pending_delivery key so matcher doesn't re-broadcast this order
	if h.redis != nil {
		ctx := context.Background()
		h.redis.Del(ctx, "pending_delivery:"+orderID)
		// Clean up rejected riders set since order is now accepted
		h.redis.Del(ctx, "rejected_riders:"+orderID)
	}

	// Notify customer that a delivery partner accepted their order
	customerID, _ := order["customer_id"].(string)
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
		if h.broadcaster != nil {
			// Send notification for the toast / push
			h.broadcaster.BroadcastNotification(customerID, "Delivery Partner Assigned",
				"A delivery partner is on the way for order "+orderNumber, "delivery_update")
			// Also send order_update with delivery partner details so the
			// customer's order list updates instantly without a server round-trip
			h.broadcaster.BroadcastOrderUpdateFull(customerID, orderID, currentStatus,
				"Delivery partner assigned", map[string]interface{}{
					"delivery_partner_id":    userID,
					"delivery_partner_name":  partnerName,
					"delivery_partner_phone": partnerPhone,
				})
		}
	}

	// Also notify restaurant owner that a rider accepted the order
	if h.broadcaster != nil {
		restaurantID, _ := order["restaurant_id"].(string)
		if restaurantID != "" {
			restaurant, restErr := h.appwrite.GetRestaurant(restaurantID)
			if restErr == nil && restaurant != nil {
				ownerID, _ := restaurant["owner_id"].(string)
				if ownerID != "" {
					h.broadcaster.BroadcastNotification(ownerID, "Rider Assigned",
						"A delivery partner has been assigned to order "+orderNumber, "delivery_update")
					h.broadcaster.BroadcastOrderUpdateFull(ownerID, orderID, currentStatus,
						"Delivery partner assigned to order "+orderNumber, map[string]interface{}{
							"delivery_partner_id":    userID,
							"delivery_partner_name":  partnerName,
							"delivery_partner_phone": partnerPhone,
						})
				}
			}
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

	// Enrich with user profile fields (name/phone/avatar) when absent in
	// delivery_partners collection. These fields are stored in users.
	if user, userErr := h.appwrite.GetUser(userID); userErr == nil && user != nil {
		if _, ok := partner["name"]; !ok || partner["name"] == nil || partner["name"] == "" {
			if name, _ := user["name"].(string); name != "" {
				partner["name"] = name
			}
		}
		if _, ok := partner["phone"]; !ok || partner["phone"] == nil || partner["phone"] == "" {
			if phone, _ := user["phone"].(string); phone != "" {
				partner["phone"] = phone
			}
		}
		if _, ok := partner["avatar_url"]; !ok || partner["avatar_url"] == nil || partner["avatar_url"] == "" {
			if avatar, _ := user["avatar_url"].(string); avatar != "" {
				partner["avatar_url"] = avatar
			}
		}
	}

	partnerID, _ := partner["$id"].(string)
	return partner, partnerID, true
}

// resolveDeliveryPartnerDetails returns (name, phone) for a delivery partner.
// It checks the delivery_partners collection first, then falls back to the
// users collection because name/phone may only be stored there.
func (h *DeliveryHandler) resolveDeliveryPartnerDetails(userID string) (string, string) {
	var name, phone string
	if dp, dpErr := h.appwrite.GetDeliveryPartner(userID); dpErr == nil && dp != nil && dp.Total > 0 {
		name, _ = dp.Documents[0]["name"].(string)
		phone, _ = dp.Documents[0]["phone"].(string)
	}
	if name == "" || phone == "" {
		if user, uErr := h.appwrite.GetUser(userID); uErr == nil && user != nil {
			if name == "" {
				if n, _ := user["name"].(string); n != "" {
					name = n
				}
			}
			if phone == "" {
				if p, _ := user["phone"].(string); p != "" {
					phone = p
				}
			}
		}
	}
	return name, phone
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

	var allDocs []map[string]interface{}
	totalCount := 0

	if mode == "available" {
		// Query both null and empty delivery_partner_id (Appwrite has no OR, so we merge)
		queriesNull := []string{
			appwrite.QueryEqual("status", models.OrderStatusReady),
			appwrite.QueryIsNull("delivery_partner_id"),
			appwrite.QueryOrderDesc("placed_at"),
			appwrite.QueryLimit(pg.PerPage),
			appwrite.QueryOffset(pg.Offset()),
		}
		resultNull, err := h.appwrite.ListOrders(queriesNull)
		if err != nil {
			utils.InternalError(c, "Failed to fetch orders")
			return
		}

		queriesEmpty := []string{
			appwrite.QueryEqual("status", models.OrderStatusReady),
			appwrite.QueryEqual("delivery_partner_id", ""),
			appwrite.QueryOrderDesc("placed_at"),
			appwrite.QueryLimit(pg.PerPage),
			appwrite.QueryOffset(pg.Offset()),
		}
		resultEmpty, errE := h.appwrite.ListOrders(queriesEmpty)

		// Merge and deduplicate
		seen := make(map[string]bool)
		if resultNull != nil {
			for _, d := range resultNull.Documents {
				id, _ := d["$id"].(string)
				if !seen[id] {
					seen[id] = true
					allDocs = append(allDocs, d)
				}
			}
			totalCount = resultNull.Total
		}
		if errE == nil && resultEmpty != nil {
			for _, d := range resultEmpty.Documents {
				id, _ := d["$id"].(string)
				if !seen[id] {
					seen[id] = true
					allDocs = append(allDocs, d)
				}
			}
			if resultEmpty.Total > totalCount {
				totalCount = resultEmpty.Total
			}
		}
	} else {
		// Show orders assigned to this partner
		queries := []string{
			appwrite.QueryEqual("delivery_partner_id", userID),
			appwrite.QueryOrderDesc("placed_at"),
			appwrite.QueryLimit(pg.PerPage),
			appwrite.QueryOffset(pg.Offset()),
		}
		result, err := h.appwrite.ListOrders(queries)
		if err != nil {
			utils.InternalError(c, "Failed to fetch orders")
			return
		}
		allDocs = result.Documents
		totalCount = result.Total
	}

	// Enrich orders with customer name/phone and delivery partner details
	for _, order := range allDocs {
		if custID, _ := order["customer_id"].(string); custID != "" {
			if _, exists := order["customer_name"]; !exists || order["customer_name"] == nil {
				if user, uErr := h.appwrite.GetUser(custID); uErr == nil && user != nil {
					if name, _ := user["name"].(string); name != "" {
						order["customer_name"] = name
					}
					if phone, _ := user["phone"].(string); phone != "" {
						order["customer_phone"] = phone
					}
				}
			}
		}
		if dpID, _ := order["delivery_partner_id"].(string); dpID != "" {
			existingDPName, _ := order["delivery_partner_name"].(string)
			existingDPPhone, _ := order["delivery_partner_phone"].(string)
			if existingDPName == "" || existingDPPhone == "" {
				dpName, dpPhone := h.resolveDeliveryPartnerDetails(dpID)
				if dpName != "" {
					order["delivery_partner_name"] = dpName
				}
				if dpPhone != "" {
					order["delivery_partner_phone"] = dpPhone
				}
			}
		}
	}

	utils.Paginated(c, allDocs, pg.Page, pg.PerPage, totalCount)
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
		case models.OrderStatusReady:
			// Order accepted but not yet picked up — still the active delivery
			if activeDeliveryOrder == nil {
				activeDeliveryOrder = order
			}
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
	weeklyEarningsCurrent := 0.0
	if weekResult != nil {
		weeklyCompleted = len(weekResult.Documents)
		for _, wo := range weekResult.Documents {
			weeklyEarningsCurrent += getFloat(wo, "delivery_fee") + getFloat(wo, "tip")
		}
	}

	isOnline, _ := partner["is_online"].(bool)
	rating, _ := partner["rating"].(float64)
	totalDeliveries := getFloat(partner, "total_deliveries")
	totalEarnings := getFloat(partner, "total_earnings")
	vehicleType, _ := partner["vehicle_type"].(string)
	vehicleNumber, _ := partner["vehicle_number"].(string)

	// Extract additional fields Flutter DeliveryPartner.fromDashboard() expects
	partnerID, _ := partner["$id"].(string)
	partnerUserID, _ := partner["user_id"].(string)
	partnerName, _ := partner["name"].(string)
	partnerPhone, _ := partner["phone"].(string)
	avatarURL, _ := partner["avatar_url"].(string)
	curLat := getFloat(partner, "current_latitude")
	curLng := getFloat(partner, "current_longitude")

	// Calculate hours online today from login_at if available
	hoursOnlineToday := 0.0
	if loginAt, ok := partner["login_at"].(string); ok && loginAt != "" {
		if t, err := time.Parse(time.RFC3339, loginAt); err == nil && isOnline {
			hoursOnlineToday = time.Since(t).Hours()
		}
	}

	// Tips today
	tipsToday := 0.0
	for _, order := range orderResult.Documents {
		status, _ := order["status"].(string)
		if status == models.OrderStatusDelivered {
			tipsToday += getFloat(order, "tip")
		}
	}

	resp := gin.H{
		"$id":                     partnerID,
		"user_id":                 partnerUserID,
		"name":                    partnerName,
		"phone":                   partnerPhone,
		"avatar_url":              avatarURL,
		"is_online":               isOnline,
		"rating":                  rating,
		"total_deliveries":        int(totalDeliveries),
		"total_earnings":          totalEarnings,
		"vehicle_type":            vehicleType,
		"vehicle_number":          vehicleNumber,
		"today_earnings":          todayEarnings,
		"today_deliveries":        todayDeliveries,
		"today_distance_km":       todayDistanceKm,
		"weekly_goal":             50,
		"weekly_completed":        weeklyCompleted,
		"weekly_earnings_goal":    15000.0,
		"weekly_earnings_current": weeklyEarningsCurrent,
		"current_latitude":        curLat,
		"current_longitude":       curLng,
		"hours_online_today":      hoursOnlineToday,
		"tips_today":              tipsToday,
		"is_on_delivery":          activeDeliveryOrder != nil,
	}

	if activeDeliveryOrder != nil {
		// Map delivery_* fields to customer_* so frontend gets correct coordinates.
		// Order stores delivery_latitude/longitude/address but frontend expects customer_*.
		if _, ok := activeDeliveryOrder["customer_latitude"]; !ok {
			activeDeliveryOrder["customer_latitude"] = activeDeliveryOrder["delivery_latitude"]
		}
		if _, ok := activeDeliveryOrder["customer_longitude"]; !ok {
			activeDeliveryOrder["customer_longitude"] = activeDeliveryOrder["delivery_longitude"]
		}
		if _, ok := activeDeliveryOrder["customer_address"]; !ok {
			activeDeliveryOrder["customer_address"] = activeDeliveryOrder["delivery_address"]
		}

		// Enrich active order with customer name/phone and delivery partner details
		if custID, _ := activeDeliveryOrder["customer_id"].(string); custID != "" {
			if _, exists := activeDeliveryOrder["customer_name"]; !exists || activeDeliveryOrder["customer_name"] == nil {
				if user, uErr := h.appwrite.GetUser(custID); uErr == nil && user != nil {
					if name, _ := user["name"].(string); name != "" {
						activeDeliveryOrder["customer_name"] = name
					}
					if phone, _ := user["phone"].(string); phone != "" {
						activeDeliveryOrder["customer_phone"] = phone
					}
				}
			}
		}
		// Enrich with restaurant phone (fall back to owner's phone)
		if restID, _ := activeDeliveryOrder["restaurant_id"].(string); restID != "" {
			if _, exists := activeDeliveryOrder["restaurant_phone"]; !exists || activeDeliveryOrder["restaurant_phone"] == nil {
				if rest, restErr := h.appwrite.GetRestaurant(restID); restErr == nil && rest != nil {
					if phone, _ := rest["phone"].(string); phone != "" {
						activeDeliveryOrder["restaurant_phone"] = phone
					} else if ownerID, _ := rest["owner_id"].(string); ownerID != "" {
						if owner, oErr := h.appwrite.GetUser(ownerID); oErr == nil && owner != nil {
							if oPhone, _ := owner["phone"].(string); oPhone != "" {
								activeDeliveryOrder["restaurant_phone"] = oPhone
							}
						}
					}
					if addr, _ := rest["address"].(string); addr != "" {
						if _, addrExists := activeDeliveryOrder["restaurant_address"]; !addrExists || activeDeliveryOrder["restaurant_address"] == nil {
							activeDeliveryOrder["restaurant_address"] = addr
						}
					}
				}
			}
		}
		if dpID, _ := activeDeliveryOrder["delivery_partner_id"].(string); dpID != "" {
			existingDPName, _ := activeDeliveryOrder["delivery_partner_name"].(string)
			existingDPPhone, _ := activeDeliveryOrder["delivery_partner_phone"].(string)
			if existingDPName == "" || existingDPPhone == "" {
				dpName, dpPhone := h.resolveDeliveryPartnerDetails(dpID)
				if dpName != "" {
					activeDeliveryOrder["delivery_partner_name"] = dpName
				}
				if dpPhone != "" {
					activeDeliveryOrder["delivery_partner_phone"] = dpPhone
				}
			}
		}
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

			// Resolve restaurant name
			restName := "Restaurant"
			if restID != "" {
				if rest, rErr := h.appwrite.GetRestaurant(restID); rErr == nil && rest != nil {
					if n, ok := rest["name"].(string); ok {
						restName = n
					}
				}
			}

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
				"restaurant_name": restName,
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
		"period":        period,
		"weekly_total":  totalEarnings,
		"monthly_total": monthlyTotal,
		"total_tips":    totalTips,
		"total_trips":   len(result.Documents),
		"weekly_data":   weeklyData,
		"recent_trips":  recentTrips,
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
		"total_orders":          totalOrders,
		"delivered_orders":      deliveredOrders,
		"cancelled_orders":      cancelledOrders,
		"completion_rate":       completionRate,
		"cancellation_rate":     cancellationRate,
		"avg_delivery_time_min": avgDeliveryTimeMin,
		"daily_trend":           dailyTrend,
		"peak_day":              peakDay,
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
	if req.BankAccountHolder != "" {
		updateData["bank_account_holder"] = req.BankAccountHolder
	}
	if req.IFSC != "" {
		updateData["ifsc"] = req.IFSC
	}
	if req.UpiID != "" {
		updateData["upi_id"] = req.UpiID
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

	// Verify order exists
	order, err := h.appwrite.GetOrder(orderID)
	if err != nil {
		utils.NotFound(c, "Order not found")
		return
	}

	// Clear the pending_delivery key so matcher can re-broadcast to other riders
	if h.redis != nil {
		ctx := context.Background()
		h.redis.Del(ctx, "pending_delivery:"+orderID)
		// Track this rider as having rejected the order so matcher won't re-send to them
		rejectedKey := "rejected_riders:" + orderID
		h.redis.SAdd(ctx, rejectedKey, userID)
		h.redis.Expire(ctx, rejectedKey, 30*time.Minute)
	}

	// Immediately retry matching so the next eligible rider gets the request
	// without waiting for the next ticker interval.
	if h.matcherCallback != nil {
		go h.matcherCallback()
	}

	// If the order was already assigned to this partner, unassign
	assignedPartner, _ := order["delivery_partner_id"].(string)
	if assignedPartner == userID {
		_, err = h.appwrite.UpdateOrder(orderID, map[string]interface{}{
			"delivery_partner_id": "",
		})
		if err != nil {
			utils.InternalError(c, "Failed to reject order")
			return
		}
	}

	utils.Success(c, gin.H{"message": "Order rejected", "order_id": orderID})
}

// ReportIssue allows a delivery partner to report an issue on an active order
// @Summary Report a delivery issue
// @Description Reports an issue for an order assigned to the authenticated delivery partner and notifies customer/restaurant
// @Tags Delivery
// @Accept json
// @Produce json
// @Param id path string true "Order ID"
// @Param request body object{reason=string,details=string} true "Issue reason and details"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]string
// @Failure 401 {object} map[string]string
// @Failure 403 {object} map[string]string
// @Failure 404 {object} map[string]string
// @Failure 500 {object} map[string]string
// @Security BearerAuth
// @Router /api/v1/delivery/orders/{id}/report [post]
func (h *DeliveryHandler) ReportIssue(c *gin.Context) {
	orderID := c.Param("id")
	userID := middleware.GetUserID(c)

	var req struct {
		Reason  string `json:"reason" binding:"required"`
		Details string `json:"details"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Reason is required")
		return
	}

	reason := strings.TrimSpace(req.Reason)
	details := strings.TrimSpace(req.Details)
	if reason == "" {
		utils.BadRequest(c, "Reason is required")
		return
	}

	order, err := h.appwrite.GetOrder(orderID)
	if err != nil {
		utils.NotFound(c, "Order not found")
		return
	}

	assignedPartner, _ := order["delivery_partner_id"].(string)
	if assignedPartner != userID {
		utils.Forbidden(c, "You are not assigned to this order")
		return
	}

	status, _ := order["status"].(string)
	allowed := status == models.OrderStatusReady || status == models.OrderStatusPickedUp || status == models.OrderStatusOutForDelivery
	if !allowed {
		utils.BadRequest(c, "Issue reporting is only allowed for active deliveries")
		return
	}

	orderNumber, _ := order["order_number"].(string)
	if orderNumber == "" {
		orderNumber = orderID
	}

	body := "Delivery partner reported an issue on order " + orderNumber + ": " + reason
	if details != "" {
		body += " (" + details + ")"
	}

	// Persist delivery issue record
	_, issueErr := h.appwrite.CreateDeliveryIssue("unique()", map[string]interface{}{
		"order_id":            orderID,
		"reporter_id":         userID,
		"delivery_partner_id": assignedPartner,
		"reason":              reason,
		"details":             details,
		"order_status":        status,
		"order_number":        orderNumber,
		"review_status":       "open",
		"created_at":          time.Now().Format(time.RFC3339),
	})
	if issueErr != nil {
		log.Printf("[ReportIssue] Failed to persist delivery issue for order %s: %v", orderID, issueErr)
	}

	// Notify customer
	if customerID, _ := order["customer_id"].(string); customerID != "" {
		_, _ = h.appwrite.CreateNotification("unique()", map[string]interface{}{
			"user_id":    customerID,
			"title":      "Delivery Issue Reported",
			"body":       body,
			"type":       "delivery_issue",
			"data":       map[string]interface{}{"order_id": orderID, "reason": reason, "details": details},
			"is_read":    false,
			"created_at": time.Now().Format(time.RFC3339),
		})
		if h.broadcaster != nil {
			h.broadcaster.BroadcastNotification(customerID, "Delivery Issue Reported", body, "delivery_issue")
		}
	}

	// Notify restaurant owner
	if restaurantID, _ := order["restaurant_id"].(string); restaurantID != "" {
		if restaurant, restErr := h.appwrite.GetRestaurant(restaurantID); restErr == nil && restaurant != nil {
			ownerID, _ := restaurant["owner_id"].(string)
			if ownerID != "" {
				_, _ = h.appwrite.CreateNotification("unique()", map[string]interface{}{
					"user_id":    ownerID,
					"title":      "Delivery Issue Reported",
					"body":       body,
					"type":       "delivery_issue",
					"data":       map[string]interface{}{"order_id": orderID, "reason": reason, "details": details},
					"is_read":    false,
					"created_at": time.Now().Format(time.RFC3339),
				})
				if h.broadcaster != nil {
					h.broadcaster.BroadcastNotification(ownerID, "Delivery Issue Reported", body, "delivery_issue")
				}
			}
		}
	}

	utils.Success(c, gin.H{"message": "Issue reported", "order_id": orderID})
}
