package handlers

import (
	"context"
	"encoding/json"
	"time"

	"github.com/chizze/backend/internal/middleware"
	"github.com/chizze/backend/internal/models"
	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/pkg/appwrite"
	redispkg "github.com/chizze/backend/pkg/redis"
	"github.com/chizze/backend/pkg/utils"
	"github.com/gin-gonic/gin"
)

// OrderHandler handles order endpoints
type OrderHandler struct {
	appwrite *services.AppwriteService
	orders   *services.OrderService
	geo      *services.GeoService
	redis    *redispkg.Client
}

// NewOrderHandler creates an order handler
func NewOrderHandler(aw *services.AppwriteService, os *services.OrderService, geo *services.GeoService, redis *redispkg.Client) *OrderHandler {
	return &OrderHandler{appwrite: aw, orders: os, geo: geo, redis: redis}
}

// PlaceOrder creates a new order with server-side price verification
// POST /api/v1/orders
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

	// --- 3. Server-side price verification for each item ---
	itemTotal := 0.0
	verifiedItems := make([]map[string]interface{}, 0, len(req.Items))
	for _, item := range req.Items {
		menuItem, err := h.appwrite.GetMenuItem(item.ItemID)
		if err != nil {
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

	// --- 5. Calculate fees ---
	deliveryFee, platformFee, gst := h.orders.CalculateFees(itemTotal, distanceKm)

	// --- 6. Apply coupon ---
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
						// Rolled past limit — revert and reject coupon
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

	// --- 7. Serialize items as JSON string ---
	itemsJSON, _ := json.Marshal(verifiedItems)

	// --- 8. Address snapshot ---
	addrSnapshot, _ := json.Marshal(map[string]interface{}{
		"label":     address["label"],
		"address":   address["address"],
		"latitude":  addrLat,
		"longitude": addrLng,
	})

	// --- 9. Estimate delivery time ---
	prepTime := 15.0 // default
	if pt, ok := restaurant["avg_prep_time"].(float64); ok && pt > 0 {
		prepTime = pt
	}
	estDeliveryMin := h.geo.EstimateDeliveryTime(distanceKm, int(prepTime))

	orderNumber := h.orders.GenerateOrderNumber()

	orderData := map[string]interface{}{
		"order_number":             orderNumber,
		"customer_id":              userID,
		"restaurant_id":            req.RestaurantID,
		"delivery_address_id":      req.DeliveryAddressID,
		"delivery_address_snapshot": string(addrSnapshot),
		"items":                    string(itemsJSON),
		"item_total":               itemTotal,
		"delivery_fee":             deliveryFee,
		"platform_fee":             platformFee,
		"gst":                      gst,
		"discount":                 discount,
		"coupon_code":              req.CouponCode,
		"tip":                      tip,
		"grand_total":              grandTotal,
		"distance_km":              distanceKm,
		"payment_method":           req.PaymentMethod,
		"payment_status":           models.PaymentPending,
		"status":                   models.OrderStatusPlaced,
		"special_instructions":     req.SpecialInstructions,
		"delivery_instructions":    req.DeliveryInstructions,
		"estimated_delivery_min":   estDeliveryMin,
		"placed_at":                time.Now().Format(time.RFC3339),
	}

	doc, err := h.appwrite.CreateOrder("unique()", orderData)
	if err != nil {
		utils.InternalError(c, "Failed to create order")
		return
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
// GET /api/v1/orders/:id
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

	utils.Success(c, order)
}

// ListOrders returns paginated order history for current user
// GET /api/v1/orders
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
	utils.Paginated(c, result.Documents, pg.Page, pg.PerPage, result.Total)
}

// CancelOrder cancels an order with ownership check
// PUT /api/v1/orders/:id/cancel
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
	utils.Success(c, updated)
}

// UpdateStatus updates order status with role-based validation
// PUT /api/v1/orders/:id/status
func (h *OrderHandler) UpdateStatus(c *gin.Context) {
	userID := middleware.GetUserID(c)
	role := middleware.GetUserRole(c)
	orderID := c.Param("id")

	var req struct {
		Status string `json:"status" binding:"required"`
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
		models.OrderStatusConfirmed: true,
		models.OrderStatusPreparing: true,
		models.OrderStatusReady:     true,
	}
	deliveryStatuses := map[string]bool{
		models.OrderStatusPickedUp:       true,
		models.OrderStatusOutForDelivery: true,
		models.OrderStatusDelivered:      true,
	}

	switch role {
	case "restaurant_owner":
		if !restOwnerStatuses[req.Status] {
			utils.Forbidden(c, "Restaurant owners can only set confirmed/preparing/ready")
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
			utils.Forbidden(c, "Delivery partners can only set picked_up/out_for_delivery/delivered")
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
	case models.OrderStatusPickedUp:
		updateData["picked_up_at"] = now
	case models.OrderStatusDelivered:
		updateData["delivered_at"] = now
	}

	updated, err := h.appwrite.UpdateOrder(orderID, updateData)
	if err != nil {
		utils.InternalError(c, "Failed to update order status")
		return
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
