package handlers

import (
	"context"
	"encoding/json"
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
)

// OrderHandler handles order endpoints
type OrderHandler struct {
	appwrite        *services.AppwriteService
	orders          *services.OrderService
	geo             *services.GeoService
	redis           *redispkg.Client
	broadcaster     *websocket.EventBroadcaster
	matcherCallback func() // called when an order becomes "ready" to trigger instant matching
}

// SetMatcherCallback registers a function to be called when an order becomes
// "ready", so that the delivery matcher can be triggered immediately instead
// of waiting for the next ticker interval.
func (h *OrderHandler) SetMatcherCallback(fn func()) {
	h.matcherCallback = fn
}

// resolveDeliveryPartnerDetails returns (name, phone) for a delivery partner.
// It checks the delivery_partners collection first, then falls back to the
// users collection because name/phone are stored in users, not delivery_partners.
func (h *OrderHandler) resolveDeliveryPartnerDetails(userID string) (string, string) {
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

// NewOrderHandler creates an order handler
func NewOrderHandler(aw *services.AppwriteService, os *services.OrderService, geo *services.GeoService, redis *redispkg.Client, broadcaster ...*websocket.EventBroadcaster) *OrderHandler {
	h := &OrderHandler{appwrite: aw, orders: os, geo: geo, redis: redis}
	if len(broadcaster) > 0 {
		h.broadcaster = broadcaster[0]
	}
	return h
}

// PlaceOrder creates a new order with server-side price verification
// @Summary Place a new order
// @Description Creates a new order with server-side price verification, fee calculation, and coupon application
// @Tags Orders
// @Accept json
// @Produce json
// @Param order body models.PlaceOrderRequest true "Order details"
// @Param X-Idempotency-Key header string false "Idempotency key to prevent duplicate orders"
// @Success 201 {object} map[string]interface{}
// @Failure 400 {object} map[string]string
// @Failure 401 {object} map[string]string
// @Failure 403 {object} map[string]string
// @Failure 500 {object} map[string]string
// @Security BearerAuth
// @Router /api/v1/orders [post]
func (h *OrderHandler) PlaceOrder(c *gin.Context) {
	userID := middleware.GetUserID(c)

	// --- Idempotency key check ---
	idempotencyKey := c.GetHeader("X-Idempotency-Key")
	if idempotencyKey != "" && h.redis != nil {
		ctx := context.Background()
		cacheKey := "idempotency:" + userID + ":" + idempotencyKey
		cached, err := h.redis.Get(ctx, cacheKey)
		if err == nil && cached != "" {
			// Return cached response
			var cachedResp map[string]interface{}
			if json.Unmarshal([]byte(cached), &cachedResp) == nil {
				utils.Created(c, cachedResp)
				return
			}
		}
	}

	var req models.PlaceOrderRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Invalid order data")
		return
	}

	// --- Normalize payment method ---
	// "razorpay" is a gateway name, not a payment method; normalize it to "online"
	switch req.PaymentMethod {
	case "cod", "upi", "card", "wallet", "netbanking", "online":
		// valid — keep as-is
	case "razorpay":
		req.PaymentMethod = "online"
	default:
		utils.BadRequest(c, "Invalid payment method: "+req.PaymentMethod)
		return
	}

	// --- 1. Verify restaurant exists & is online ---
	restaurant, err := h.appwrite.GetRestaurant(req.RestaurantID)
	if err != nil {
		utils.BadRequest(c, "Restaurant not found")
		return
	}
	isOnline, _ := restaurant["is_online"].(bool)
	if !isOnline {
		utils.BadRequest(c, "Restaurant is currently offline")
		return
	}

	// --- 2. Get delivery address ---
	address, err := h.appwrite.GetAddress(req.DeliveryAddressID)
	if err != nil {
		utils.BadRequest(c, "Delivery address not found")
		return
	}
	addrUserID, _ := address["user_id"].(string)
	if addrUserID != userID {
		utils.Forbidden(c, "This address does not belong to you")
		return
	}

	// --- 3. Server-side price verification (batch fetch to avoid N+1) ---
	itemIDs := make([]string, len(req.Items))
	for i, item := range req.Items {
		itemIDs[i] = item.ItemID
	}
	menuResult, err := h.appwrite.ListMenuItemsByIDs(itemIDs)
	if err != nil {
		utils.BadRequest(c, "Failed to fetch menu items")
		return
	}
	// Index fetched items by ID for O(1) lookup
	menuByID := make(map[string]map[string]interface{}, len(menuResult.Documents))
	for _, doc := range menuResult.Documents {
		id, _ := doc["$id"].(string)
		menuByID[id] = doc
	}

	itemTotal := 0.0
	verifiedItems := make([]map[string]interface{}, 0, len(req.Items))
	for _, item := range req.Items {
		menuItem, ok := menuByID[item.ItemID]
		if !ok {
			utils.BadRequest(c, "Menu item not found: "+item.ItemID)
			return
		}
		// Check item belongs to restaurant
		itemRestID, _ := menuItem["restaurant_id"].(string)
		if itemRestID != req.RestaurantID {
			utils.BadRequest(c, "Item does not belong to the selected restaurant")
			return
		}
		isAvailable, _ := menuItem["is_available"].(bool)
		if !isAvailable {
			utils.BadRequest(c, "Item is unavailable: "+item.Name)
			return
		}
		serverPrice, _ := menuItem["price"].(float64)
		lineTotal := serverPrice * float64(item.Quantity)
		itemTotal += lineTotal

		verifiedItems = append(verifiedItems, map[string]interface{}{
			"item_id":  item.ItemID,
			"name":     menuItem["name"],
			"quantity": item.Quantity,
			"price":    serverPrice,
			"is_veg":   menuItem["is_veg"],
		})
	}

	// --- 4. Calculate distance ---
	restLat, _ := restaurant["latitude"].(float64)
	restLng, _ := restaurant["longitude"].(float64)
	addrLat, _ := address["latitude"].(float64)
	addrLng, _ := address["longitude"].(float64)
	distanceKm := h.geo.Distance(restLat, restLng, addrLat, addrLng)
	if distanceKm > 20.0 {
		utils.BadRequest(c, "Delivery address is too far from restaurant")
		return
	}

	// --- 5. Normalize delivery type ---
	deliveryType := req.DeliveryType
	if deliveryType != "eco" {
		deliveryType = "standard"
	}

	// --- 6. Calculate fees ---
	deliveryFee, platformFee, gst := h.orders.CalculateFees(itemTotal, distanceKm, deliveryType)

	// --- 7. Apply coupon ---
	discount := 0.0
	if req.CouponCode != "" {
		coupon, err := h.appwrite.GetCoupon(req.CouponCode)
		if err == nil && coupon != nil {
			// Parse coupon
			var c models.Coupon
			c.Code, _ = coupon["code"].(string)
			c.DiscountType, _ = coupon["discount_type"].(string)
			c.DiscountValue, _ = coupon["discount_value"].(float64)
			c.MinOrderValue, _ = coupon["min_order_value"].(float64)
			c.MaxDiscount, _ = coupon["max_discount"].(float64)
			c.UsedCount = int(getFloat(coupon, "used_count"))
			c.UsageLimit = int(getFloat(coupon, "usage_limit"))

			// Parse dates as strings from Appwrite
			validFromStr, _ := coupon["valid_from"].(string)
			validUntilStr, _ := coupon["valid_until"].(string)
			if validFromStr != "" {
				c.ValidFrom, _ = time.Parse(time.RFC3339, validFromStr)
			}
			if validUntilStr != "" {
				c.ValidUntil, _ = time.Parse(time.RFC3339, validUntilStr)
			}
			isActive, _ := coupon["is_active"].(bool)
			c.IsActive = isActive

			if valid, _ := c.IsValid(itemTotal); valid {
				discount = c.CalculateDiscount(itemTotal)
				couponID, _ := coupon["$id"].(string)
				// Atomic increment via Redis to prevent race condition
				if h.redis != nil {
					ctx := context.Background()
					lockKey := "coupon_usage:" + couponID
					newCount, _ := h.redis.Incr(ctx, lockKey)
					if newCount == 1 {
						_ = h.redis.Expire(ctx, lockKey, 30*24*time.Hour)
					}
					if int(newCount) > c.UsageLimit {
						// Rolled past limit — revert counter and reject coupon
						h.redis.Decr(ctx, lockKey)
						discount = 0
					} else {
						_, _ = h.appwrite.UpdateCoupon(couponID, map[string]interface{}{
							"used_count": int(newCount),
						})
					}
				} else {
					// Fallback without Redis — original behavior
					_, _ = h.appwrite.UpdateCoupon(couponID, map[string]interface{}{
						"used_count": c.UsedCount + 1,
					})
				}
			}
		}
	}

	tip := req.Tip
	if tip < 0 {
		tip = 0
	}
	grandTotal := itemTotal + deliveryFee + platformFee + gst - discount + tip

	// --- 8. Serialize items as JSON string ---
	itemsJSON, _ := json.Marshal(verifiedItems)

	// --- 9. Address snapshot — store address data in order for historical reference ---
	deliveryAddress, _ := address["full_address"].(string)
	deliveryLandmark, _ := address["landmark"].(string)

	// --- 10. Estimate delivery time ---
	prepTime := 15.0 // default
	if pt, ok := restaurant["avg_prep_time"].(float64); ok && pt > 0 {
		prepTime = pt
	}
	estDeliveryMin := h.geo.EstimateDeliveryTime(distanceKm, int(prepTime))

	orderNumber := h.orders.GenerateOrderNumber()

	// Get restaurant name for denormalized storage
	restaurantName, _ := restaurant["name"].(string)

	orderData := map[string]interface{}{
		"order_number":           orderNumber,
		"customer_id":            userID,
		"restaurant_id":          req.RestaurantID,
		"restaurant_name":        restaurantName,
		"restaurant_latitude":    restLat,
		"restaurant_longitude":   restLng,
		"delivery_address_id":    req.DeliveryAddressID,
		"delivery_address":       deliveryAddress,
		"delivery_landmark":      deliveryLandmark,
		"delivery_latitude":      addrLat,
		"delivery_longitude":     addrLng,
		"items":                  string(itemsJSON),
		"item_total":             itemTotal,
		"delivery_type":          deliveryType,
		"delivery_fee":           deliveryFee,
		"platform_fee":           platformFee,
		"gst":                    gst,
		"discount":               discount,
		"coupon_code":            req.CouponCode,
		"tip":                    tip,
		"grand_total":            grandTotal,
		"payment_method":         req.PaymentMethod,
		"payment_status":         models.PaymentPending,
		"status":                 models.OrderStatusPlaced,
		"special_instructions":   req.SpecialInstructions,
		"delivery_instructions":  req.DeliveryInstructions,
		"estimated_delivery_min": estDeliveryMin,
		"placed_at":              time.Now().Format(time.RFC3339),
	}

	doc, err := h.appwrite.CreateOrder("unique()", orderData)
	if err != nil {
		log.Printf("[ERROR] CreateOrder failed for user=%s restaurant=%s payment_method=%s: %v",
			userID, req.RestaurantID, req.PaymentMethod, err)
		utils.InternalError(c, "Failed to create order")
		return
	}

	// Broadcast new order to restaurant owner via WebSocket
	if h.broadcaster != nil {
		ownerID, _ := restaurant["owner_id"].(string)
		if ownerID != "" {
			orderID, _ := doc["$id"].(string)

			// Get customer name for the broadcast
			customerName := "Customer"
			if user, uErr := h.appwrite.GetUser(userID); uErr == nil && user != nil {
				if name, _ := user["name"].(string); name != "" {
					customerName = name
				}
			}

			h.broadcaster.BroadcastNewOrder(ownerID, orderID, map[string]interface{}{
				"order_number":       orderNumber,
				"restaurant_name":    restaurantName,
				"grand_total":        grandTotal,
				"items_count":        len(verifiedItems),
				"customer_name":      customerName,
				"delivery_address":   deliveryAddress,
				"delivery_landmark":  deliveryLandmark,
				"items":              verifiedItems,
				"payment_method":     req.PaymentMethod,
				"special_instructions": req.SpecialInstructions,
			})
		}
	}

	// Cache idempotency response (24h TTL)
	if idempotencyKey != "" && h.redis != nil {
		ctx := context.Background()
		cacheKey := "idempotency:" + userID + ":" + idempotencyKey
		if respJSON, err := json.Marshal(doc); err == nil {
			_ = h.redis.Set(ctx, cacheKey, string(respJSON), 24*time.Hour)
		}
	}

	utils.Created(c, doc)
}

// GetOrder returns order details with ownership check
// @Summary Get order details
// @Description Returns order details with role-based ownership check
// @Tags Orders
// @Accept json
// @Produce json
// @Param id path string true "Order ID"
// @Success 200 {object} map[string]interface{}
// @Failure 401 {object} map[string]string
// @Failure 403 {object} map[string]string
// @Failure 404 {object} map[string]string
// @Security BearerAuth
// @Router /api/v1/orders/{id} [get]
func (h *OrderHandler) GetOrder(c *gin.Context) {
	userID := middleware.GetUserID(c)
	role := middleware.GetUserRole(c)
	orderID := c.Param("id")

	order, err := h.appwrite.GetOrder(orderID)
	if err != nil {
		utils.NotFound(c, "Order not found")
		return
	}

	// Ownership: customers see their own, partners see their restaurant's, delivery sees assigned
	custID, _ := order["customer_id"].(string)
	restID, _ := order["restaurant_id"].(string)
	deliveryID, _ := order["delivery_partner_id"].(string)

	switch role {
	case "customer":
		if custID != userID {
			utils.Forbidden(c, "Access denied")
			return
		}
	case "restaurant_owner":
		result, err := h.appwrite.GetRestaurantByOwner(userID)
		if err != nil || result == nil || len(result.Documents) == 0 {
			utils.Forbidden(c, "Access denied")
			return
		}
		myRestID, _ := result.Documents[0]["$id"].(string)
		if restID != myRestID {
			utils.Forbidden(c, "Access denied")
			return
		}
	case "delivery_partner":
		if deliveryID != userID {
			utils.Forbidden(c, "Access denied")
			return
		}
	default:
		utils.Forbidden(c, "Access denied")
		return
	}

	// Enrich with customer name from users collection
	if custID != "" {
		if _, exists := order["customer_name"]; !exists || order["customer_name"] == nil {
			if user, uErr := h.appwrite.GetUser(custID); uErr == nil && user != nil {
				if name, _ := user["name"].(string); name != "" {
					order["customer_name"] = name
				}
			}
		}
	}

	// Enrich with delivery partner name/phone (delivery_partners may not store
	// name/phone — fall back to users collection)
	if deliveryID != "" {
		if _, exists := order["delivery_partner_name"]; !exists || order["delivery_partner_name"] == nil {
			dpName, dpPhone := h.resolveDeliveryPartnerDetails(deliveryID)
			if dpName != "" {
				order["delivery_partner_name"] = dpName
			}
			if dpPhone != "" {
				order["delivery_partner_phone"] = dpPhone
			}
		}
	}

	utils.Success(c, order)
}

// ListOrders returns paginated order history for current user
// @Summary List orders
// @Description Returns paginated order history filtered by the current user's role
// @Tags Orders
// @Accept json
// @Produce json
// @Param status query string false "Filter by order status"
// @Param page query int false "Page number" default(1)
// @Param per_page query int false "Items per page" default(20)
// @Success 200 {object} map[string]interface{}
// @Failure 401 {object} map[string]string
// @Failure 500 {object} map[string]string
// @Security BearerAuth
// @Router /api/v1/orders [get]
func (h *OrderHandler) ListOrders(c *gin.Context) {
	userID := middleware.GetUserID(c)
	role := middleware.GetUserRole(c)
	pg := models.ParsePagination(c)

	queries := []string{
		appwrite.QueryOrderDesc("placed_at"),
		appwrite.QueryLimit(pg.PerPage),
		appwrite.QueryOffset(pg.Offset()),
	}

	// Filter by user's role
	switch role {
	case "customer":
		queries = append(queries, appwrite.QueryEqual("customer_id", userID))
	case "restaurant_owner":
		result, err := h.appwrite.GetRestaurantByOwner(userID)
		if err != nil || result == nil || len(result.Documents) == 0 {
			utils.Success(c, gin.H{"orders": []interface{}{}, "total": 0})
			return
		}
		restID, _ := result.Documents[0]["$id"].(string)
		queries = append(queries, appwrite.QueryEqual("restaurant_id", restID))
	case "delivery_partner":
		queries = append(queries, appwrite.QueryEqual("delivery_partner_id", userID))
	}

	// Optional status filter
	if status := c.Query("status"); status != "" {
		queries = append(queries, appwrite.QueryEqual("status", status))
	}

	result, err := h.appwrite.ListOrders(queries)
	if err != nil {
		utils.InternalError(c, "Failed to fetch orders")
		return
	}

	// Enrich orders with customer name/phone and delivery partner name/phone.
	// delivery_partners collection does not store name/phone — must fall back to users.
	for _, order := range result.Documents {
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
			if _, exists := order["delivery_partner_name"]; !exists || order["delivery_partner_name"] == nil {
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

	utils.Paginated(c, result.Documents, pg.Page, pg.PerPage, result.Total)
}

// CancelOrder cancels an order with ownership check
// @Summary Cancel an order
// @Description Cancels an order with ownership verification; only the customer who placed the order can cancel
// @Tags Orders
// @Accept json
// @Produce json
// @Param id path string true "Order ID"
// @Param request body models.CancelOrderRequest true "Cancellation reason"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]string
// @Failure 401 {object} map[string]string
// @Failure 403 {object} map[string]string
// @Failure 404 {object} map[string]string
// @Failure 500 {object} map[string]string
// @Security BearerAuth
// @Router /api/v1/orders/{id}/cancel [put]
func (h *OrderHandler) CancelOrder(c *gin.Context) {
	userID := middleware.GetUserID(c)
	orderID := c.Param("id")

	var req models.CancelOrderRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Cancellation reason is required")
		return
	}

	order, err := h.appwrite.GetOrder(orderID)
	if err != nil {
		utils.NotFound(c, "Order not found")
		return
	}

	// Only the customer can cancel
	custID, _ := order["customer_id"].(string)
	if custID != userID {
		utils.Forbidden(c, "You can only cancel your own orders")
		return
	}

	currentStatus, _ := order["status"].(string)
	if err := h.orders.ValidateTransition(currentStatus, models.OrderStatusCancelled); err != nil {
		utils.BadRequest(c, err.Error())
		return
	}

	now := time.Now().Format(time.RFC3339)
	updated, err := h.appwrite.UpdateOrder(orderID, map[string]interface{}{
		"status":              models.OrderStatusCancelled,
		"cancelled_at":        now,
		"cancellation_reason": req.Reason,
		"cancelled_by":        "customer",
	})
	if err != nil {
		utils.InternalError(c, "Failed to cancel order")
		return
	}

	// Broadcast cancellation via WebSocket
	if h.broadcaster != nil {
		h.broadcaster.BroadcastOrderUpdate(userID, orderID, models.OrderStatusCancelled, "Order cancelled by customer")
	}

	utils.Success(c, updated)
}

// UpdateStatus updates order status with role-based validation
// @Summary Update order status
// @Description Updates order status with role-based validation; restaurant owners set confirmed/preparing/ready/cancelled, delivery partners set pickedUp/outForDelivery/delivered
// @Tags Orders
// @Accept json
// @Produce json
// @Param id path string true "Order ID"
// @Param request body object{status=string} true "New status"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]string
// @Failure 401 {object} map[string]string
// @Failure 403 {object} map[string]string
// @Failure 404 {object} map[string]string
// @Failure 500 {object} map[string]string
// @Security BearerAuth
// @Router /api/v1/partner/orders/{id}/status [put]
func (h *OrderHandler) UpdateStatus(c *gin.Context) {
	userID := middleware.GetUserID(c)
	role := middleware.GetUserRole(c)
	orderID := c.Param("id")

	var req struct {
		Status string `json:"status" binding:"required"`
		Reason string `json:"reason"` // used when status is "cancelled"
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Status is required")
		return
	}

	order, err := h.appwrite.GetOrder(orderID)
	if err != nil {
		utils.NotFound(c, "Order not found")
		return
	}

	// Role-based authorization
	restOwnerStatuses := map[string]bool{
		models.OrderStatusConfirmed:  true,
		models.OrderStatusPreparing:  true,
		models.OrderStatusReady:      true,
		models.OrderStatusCancelled:  true,
	}
	deliveryStatuses := map[string]bool{
		models.OrderStatusPickedUp:       true,
		models.OrderStatusOutForDelivery: true,
		models.OrderStatusDelivered:      true,
	}

	switch role {
	case "restaurant_owner":
		if !restOwnerStatuses[req.Status] {
			utils.Forbidden(c, "Restaurant owners can only set confirmed/preparing/ready/cancelled")
			return
		}
		// Verify this is their restaurant's order
		result, err := h.appwrite.GetRestaurantByOwner(userID)
		if err != nil || result == nil || len(result.Documents) == 0 {
			utils.Forbidden(c, "Access denied")
			return
		}
		restID, _ := result.Documents[0]["$id"].(string)
		orderRestID, _ := order["restaurant_id"].(string)
		if restID != orderRestID {
			utils.Forbidden(c, "This order is not for your restaurant")
			return
		}
	case "delivery_partner":
		if !deliveryStatuses[req.Status] {
			utils.Forbidden(c, "Delivery partners can only set pickedUp/outForDelivery/delivered")
			return
		}
		deliveryID, _ := order["delivery_partner_id"].(string)
		if deliveryID != userID {
			utils.Forbidden(c, "You are not assigned to this order")
			return
		}
	default:
		utils.Forbidden(c, "Only restaurant owners and delivery partners can update status")
		return
	}

	currentStatus, _ := order["status"].(string)
	if err := h.orders.ValidateTransition(currentStatus, req.Status); err != nil {
		utils.BadRequest(c, err.Error())
		return
	}

	updateData := map[string]interface{}{
		"status": req.Status,
	}

	now := time.Now().Format(time.RFC3339)
	switch req.Status {
	case models.OrderStatusConfirmed:
		updateData["confirmed_at"] = now
	case models.OrderStatusReady:
		updateData["prepared_at"] = now
		// Trigger delivery matching immediately so nearest rider gets the request
		if h.matcherCallback != nil {
			go h.matcherCallback()
		}
	case models.OrderStatusPickedUp:
		updateData["picked_up_at"] = now
	case models.OrderStatusDelivered:
		updateData["delivered_at"] = now
		// Mark COD orders as paid upon delivery
		paymentMethod, _ := order["payment_method"].(string)
		if paymentMethod == "cod" {
			updateData["payment_status"] = "paid"
		}
	case models.OrderStatusCancelled:
		updateData["cancelled_at"] = now
		updateData["cancelled_by"] = role
		if req.Reason != "" {
			updateData["cancellation_reason"] = req.Reason
		}
	}

	updated, err := h.appwrite.UpdateOrder(orderID, updateData)
	if err != nil {
		utils.InternalError(c, "Failed to update order status")
		return
	}

	// Update delivery partner stats when order is delivered
	if req.Status == models.OrderStatusDelivered {
		if dpUserID, _ := order["delivery_partner_id"].(string); dpUserID != "" {
			dpResult, dpErr := h.appwrite.GetDeliveryPartner(dpUserID)
			if dpErr == nil && dpResult != nil && dpResult.Total > 0 {
				dpDoc := dpResult.Documents[0]
				dpDocID, _ := dpDoc["$id"].(string)
				currentDeliveries := getFloat(dpDoc, "total_deliveries")
				currentEarnings := getFloat(dpDoc, "total_earnings")
				// Calculate delivery earning: delivery_fee + tip from the order
				deliveryFee := getFloat(order, "delivery_fee")
				tip := getFloat(order, "tip")
				orderEarning := deliveryFee + tip
				_, _ = h.appwrite.UpdateDeliveryPartner(dpDocID, map[string]interface{}{
					"total_deliveries": int(currentDeliveries) + 1,
					"total_earnings":   currentEarnings + orderEarning,
					"current_order_id": "",
					"status":           "available",
				})
			}
		}
	}

	// Send notifications on delivery status changes
	customerID, _ := order["customer_id"].(string)
	orderNumber, _ := order["order_number"].(string)
	if customerID != "" {
		var notifTitle, notifBody string
		switch req.Status {
		case models.OrderStatusConfirmed:
			notifTitle = "Order Confirmed"
			notifBody = "Your order " + orderNumber + " has been confirmed by the restaurant"
		case models.OrderStatusPreparing:
			notifTitle = "Preparing Your Order"
			notifBody = "The restaurant is now preparing your order " + orderNumber
		case models.OrderStatusReady:
			notifTitle = "Order Ready"
			notifBody = "Your order " + orderNumber + " is ready for pickup"
		case models.OrderStatusPickedUp:
			notifTitle = "Order Picked Up"
			notifBody = "Your order " + orderNumber + " has been picked up by the delivery partner"
		case models.OrderStatusOutForDelivery:
			notifTitle = "Out for Delivery"
			notifBody = "Your order " + orderNumber + " is on its way!"
		case models.OrderStatusDelivered:
			notifTitle = "Order Delivered"
			notifBody = "Your order " + orderNumber + " has been delivered. Enjoy your meal!"
		case models.OrderStatusCancelled:
			notifTitle = "Order Cancelled"
			notifBody = "Your order " + orderNumber + " was cancelled by the restaurant"
			if req.Reason != "" {
				notifBody += ": " + req.Reason
			}
		}
		if notifTitle != "" {
			_, _ = h.appwrite.CreateNotification("unique()", map[string]interface{}{
				"user_id":    customerID,
				"title":      notifTitle,
				"body":       notifBody,
				"type":       "order_status",
				"data":       map[string]interface{}{"order_id": orderID, "status": req.Status},
				"is_read":    false,
				"created_at": now,
			})
			// Broadcast via WebSocket for instant updates to customer.
			// Include delivery partner details so the client can update UI
			// without a round-trip fetch.
			if h.broadcaster != nil {
				dpID, _ := order["delivery_partner_id"].(string)
				dpName, _ := order["delivery_partner_name"].(string)
				dpPhone, _ := order["delivery_partner_phone"].(string)
				extra := map[string]interface{}{}
				if dpID != "" {
					extra["delivery_partner_id"] = dpID
				}
				if dpName != "" {
					extra["delivery_partner_name"] = dpName
				}
				if dpPhone != "" {
					extra["delivery_partner_phone"] = dpPhone
				}
				if len(extra) > 0 {
					h.broadcaster.BroadcastOrderUpdateFull(customerID, orderID, req.Status, notifBody, extra)
				} else {
					h.broadcaster.BroadcastOrderUpdate(customerID, orderID, req.Status, notifBody)
				}
			}
		}
	}

	// Also broadcast delivery status changes to restaurant owner via WebSocket
	// so the restaurant dashboard updates instantly when rider picks up / delivers
	if h.broadcaster != nil {
		restaurantID, _ := order["restaurant_id"].(string)
		if restaurantID != "" {
			restaurant, restErr := h.appwrite.GetRestaurant(restaurantID)
			if restErr == nil && restaurant != nil {
				ownerID, _ := restaurant["owner_id"].(string)
				if ownerID != "" {
					h.broadcaster.BroadcastOrderUpdate(ownerID, orderID, req.Status, "Order "+orderNumber+" status: "+req.Status)
				}
			}
		}

		// Broadcast to delivery partner so their UI confirms the status change.
		// This is especially important if the partner's optimistic update
		// succeeded but they need server confirmation, or if the restaurant
		// changed the status (e.g. cancelled).
		if dpUserID, _ := order["delivery_partner_id"].(string); dpUserID != "" && dpUserID != userID {
			h.broadcaster.BroadcastOrderUpdate(dpUserID, orderID, req.Status, "Order "+orderNumber+" status: "+req.Status)
		}
	}

	utils.Success(c, updated)
}

// getFloat safely extracts a float64 from a map
func getFloat(m map[string]interface{}, key string) float64 {
	if v, ok := m[key].(float64); ok {
		return v
	}
	return 0
}
