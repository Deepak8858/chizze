package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"

	"github.com/chizze/backend/internal/middleware"
	"github.com/chizze/backend/internal/models"
	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/internal/websocket"
	"github.com/chizze/backend/pkg/appwrite"
	"github.com/chizze/backend/pkg/fcm"
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
	hub             *websocket.Hub // for IsConnected check (FCM fallback)
	fcmClient       *fcm.Client    // nil if FCM_SERVER_KEY not set
	matcherCallback func()         // called when an order becomes "ready" to trigger instant matching
}

// SetPushDependencies wires the WS hub + FCM client so PlaceOrder can push a
// new-order wake-up notification to the restaurant owner even when their app
// is backgrounded and the WebSocket is dead. Safe to call with nil values.
func (h *OrderHandler) SetPushDependencies(hub *websocket.Hub, fcmClient *fcm.Client) {
	h.hub = hub
	h.fcmClient = fcmClient
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
	ctx := c.Request.Context()

	// --- Idempotency key check ---
	idempotencyKey := c.GetHeader("X-Idempotency-Key")
	if idempotencyKey != "" && h.redis != nil {
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
		// Also acquire a short order-placement lock so two parallel clicks on
		// "Place Order" with the same key don't both hit CreateOrder concurrently.
		lockKey := "place_order_lock:" + userID + ":" + idempotencyKey
		acquired, lockErr := h.redis.SetNX(ctx, lockKey, "1", 15*time.Second)
		if lockErr == nil && !acquired {
			utils.Error(c, http.StatusConflict, "An identical order is already being placed. Please wait a moment.")
			return
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
		if item.Quantity <= 0 {
			utils.BadRequest(c, "Item quantity must be at least 1")
			return
		}
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
			var cp models.Coupon
			cp.Code, _ = coupon["code"].(string)
			cp.DiscountType, _ = coupon["discount_type"].(string)
			cp.DiscountValue, _ = coupon["discount_value"].(float64)
			cp.MinOrderValue, _ = coupon["min_order_value"].(float64)
			cp.MaxDiscount, _ = coupon["max_discount"].(float64)
			cp.UsedCount = int(getFloat(coupon, "used_count"))
			cp.UsageLimit = int(getFloat(coupon, "usage_limit"))

			// Parse dates as strings from Appwrite
			validFromStr, _ := coupon["valid_from"].(string)
			validUntilStr, _ := coupon["valid_until"].(string)
			if validFromStr != "" {
				cp.ValidFrom, _ = time.Parse(time.RFC3339, validFromStr)
			}
			if validUntilStr != "" {
				cp.ValidUntil, _ = time.Parse(time.RFC3339, validUntilStr)
			}
			isActive, _ := coupon["is_active"].(bool)
			cp.IsActive = isActive

			if valid, _ := cp.IsValid(itemTotal); valid {
				discount = cp.CalculateDiscount(itemTotal)
				couponID, _ := coupon["$id"].(string)
				// Atomic increment via Redis to prevent race condition.
				// UsageLimit <= 0 means unlimited — skip the ceiling check entirely
				// so the counter never spuriously rejects valid uses.
				if h.redis != nil {
					lockKey := "coupon_usage:" + couponID
					newCount, incrErr := h.redis.Incr(ctx, lockKey)
					if incrErr != nil {
						log.Printf("[WARN] coupon Redis incr failed (allowing coupon): %v", incrErr)
					} else {
						if newCount == 1 {
							_ = h.redis.Expire(ctx, lockKey, 30*24*time.Hour)
						}
						if cp.UsageLimit > 0 && int(newCount) > cp.UsageLimit {
							// Rolled past limit — revert counter and reject coupon
							_, _ = h.redis.Decr(ctx, lockKey)
							discount = 0
						} else {
							// Persist counter asynchronously so Appwrite write
							// latency/failure doesn't block the order path.
							// Redis holds the authoritative count.
							go func(id string, count int64) {
								if _, err := h.appwrite.UpdateCoupon(id, map[string]interface{}{
									"used_count": int(count),
								}); err != nil {
									log.Printf("[WARN] coupon %s persist used_count=%d failed: %v", id, count, err)
								}
							}(couponID, newCount)
						}
					}
				} else {
					// Fallback without Redis — original behavior
					_, _ = h.appwrite.UpdateCoupon(couponID, map[string]interface{}{
						"used_count": cp.UsedCount + 1,
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

	// Look up customer name and phone once — used both in the order doc and WS broadcast
	customerName := "Customer"
	customerPhone := ""
	if user, uErr := h.appwrite.GetUser(userID); uErr == nil && user != nil {
		if name, _ := user["name"].(string); name != "" {
			customerName = name
		}
		if ph, _ := user["phone"].(string); ph != "" {
			customerPhone = ph
		}
	}

	orderData := map[string]interface{}{
		"order_number":           orderNumber,
		"customer_id":            userID,
		"customer_name":          customerName,
		"customer_phone":         customerPhone,
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

	// Broadcast new order to restaurant owner via WebSocket + FCM push fallback.
	// Record delivery-attempt flags in Redis so OrderTimeout worker knows whether
	// the owner was reachable — it skips auto-cancel for orders that never
	// reached the restaurant (those need a stuck-order alert, not cancellation).
	orderID, _ := doc["$id"].(string)
	if h.broadcaster != nil {
		ownerID, _ := restaurant["owner_id"].(string)
		if ownerID != "" {

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

			// Record WS delivery attempt. Hub may be nil in tests.
			wsDelivered := false
			if h.hub != nil && h.hub.IsConnected(ownerID) {
				wsDelivered = true
			}

			// FCM wake-up: owner's phone could be locked, app backgrounded, or
			// WS heartbeat expired. Fire async so PlaceOrder latency stays low.
			// We always attempt FCM (not only on WS miss) because even when a
			// socket is open, Android may have throttled background tasks — the
			// high-priority FCM payload is the reliable wake-up path.
			fcmAttempted := false
			if h.fcmClient != nil {
				fcmAttempted = true
				go func(ownerID, orderID, restName, orderNum, custName string, total float64, itemCount int) {
					user, err := h.appwrite.GetUser(ownerID)
					if err != nil || user == nil {
						log.Printf("[order] FCM: failed to fetch owner %s: %v", ownerID, err)
						return
					}
					token, _ := user["fcm_token"].(string)
					if token == "" {
						log.Printf("[order] FCM: owner %s has no fcm_token registered — WS-only delivery for order %s", ownerID, orderID)
						return
					}
					pushErr := h.fcmClient.SendPush(
						context.Background(),
						token,
						"🍽 New Order #"+orderNum,
						fmt.Sprintf("%s • %d item(s) • ₹%.0f", custName, itemCount, total),
						map[string]string{
							"type":               "new_order",
							"order_id":           orderID,
							"order_number":       orderNum,
							"restaurant_name":    restName,
							"grand_total":        fmt.Sprintf("%.0f", total),
							"click_action":       "FLUTTER_NOTIFICATION_CLICK",
							"android_channel_id": "new_orders",
						},
					)
					if pushErr != nil {
						log.Printf("[order] FCM send failed for owner %s order %s: %v", ownerID, orderID, pushErr)
					} else {
						log.Printf("[order] FCM push sent to owner %s for order %s", ownerID, orderID)
						if h.redis != nil {
							_ = h.redis.Set(context.Background(), "order_notif:"+orderID+":fcm", "1", 30*time.Minute)
						}
					}
				}(ownerID, orderID, restaurantName, orderNumber, customerName, grandTotal, len(verifiedItems))
			}

			if h.redis != nil {
				if wsDelivered {
					_ = h.redis.Set(ctx, "order_notif:"+orderID+":ws", "1", 30*time.Minute)
				}
				if !wsDelivered && !fcmAttempted {
					log.Printf("[order] WARN: order %s placed but owner %s unreachable (no WS, no FCM configured)", orderID, ownerID)
				}
			}
		}
	}

	// Cache idempotency response (24h TTL)
	if idempotencyKey != "" && h.redis != nil {
		cacheKey := "idempotency:" + userID + ":" + idempotencyKey
		if respJSON, err := json.Marshal(doc); err == nil {
			_ = h.redis.Set(ctx, cacheKey, string(respJSON), 24*time.Hour)
		}
	}

	utils.Created(c, doc)
}

// GetTracking returns a minimal tracking payload for an order: current rider
// position (from Redis geo), rider identity, order status, restaurant + delivery
// coordinates, and an ETA estimate. Intended to hydrate the customer's live
// tracking map on first load — WebSocket `delivery_location` events keep it
// fresh after that.
//
// @Summary Get live tracking snapshot for an order
// @Description Returns rider position, status, waypoints, and ETA; only accessible by the order's customer or assigned rider.
// @Tags Orders
// @Accept json
// @Produce json
// @Param id path string true "Order ID"
// @Success 200 {object} map[string]interface{}
// @Failure 401 {object} map[string]string
// @Failure 403 {object} map[string]string
// @Failure 404 {object} map[string]string
// @Security BearerAuth
// @Router /api/v1/orders/{id}/tracking [get]
func (h *OrderHandler) GetTracking(c *gin.Context) {
	userID := middleware.GetUserID(c)
	role := middleware.GetUserRole(c)
	orderID := c.Param("id")

	order, err := h.appwrite.GetOrder(orderID)
	if err != nil {
		utils.NotFound(c, "Order not found")
		return
	}

	// Ownership: only customer / assigned rider / (restaurant owner) can view.
	custID, _ := order["customer_id"].(string)
	riderID, _ := order["delivery_partner_id"].(string)
	restID, _ := order["restaurant_id"].(string)

	switch role {
	case "customer":
		if custID != userID {
			utils.Forbidden(c, "Access denied")
			return
		}
	case "delivery_partner":
		if riderID != userID {
			utils.Forbidden(c, "Access denied")
			return
		}
	case "restaurant_owner":
		if restID != "" {
			result, lookupErr := h.appwrite.GetRestaurantByOwner(userID)
			if lookupErr != nil || result == nil || len(result.Documents) == 0 {
				utils.Forbidden(c, "Access denied")
				return
			}
			myRestID, _ := result.Documents[0]["$id"].(string)
			if restID != myRestID {
				utils.Forbidden(c, "Access denied")
				return
			}
		}
	case "admin", "super_admin":
		// Allowed.
	default:
		utils.Forbidden(c, "Access denied")
		return
	}

	status, _ := order["status"].(string)
	restLat, _ := order["restaurant_latitude"].(float64)
	restLng, _ := order["restaurant_longitude"].(float64)
	custLat, _ := order["delivery_latitude"].(float64)
	custLng, _ := order["delivery_longitude"].(float64)

	// Read rider's current position from Redis geo set. Falls back to
	// (0, 0) when the rider has no reported location yet — the client
	// treats 0/0 as "no signal" and hides the marker.
	var riderLat, riderLng float64
	if riderID != "" && h.redis != nil {
		positions, gErr := h.redis.GeoPos(c.Request.Context(), "rider_locations", riderID)
		if gErr == nil && len(positions) > 0 && positions[0] != nil {
			riderLat = positions[0].Latitude
			riderLng = positions[0].Longitude
		}
	}

	// Pick the "next waypoint" that ETA should target — restaurant if the
	// rider is still picking up, customer if they're out for delivery.
	var targetLat, targetLng float64
	switch status {
	case models.OrderStatusPickedUp, models.OrderStatusOutForDelivery:
		targetLat, targetLng = custLat, custLng
	default:
		targetLat, targetLng = restLat, restLng
	}

	// ETA in minutes based on straight-line distance when we have both
	// rider position and target. We use the same GeoService heuristic as
	// order placement so customers see consistent numbers.
	etaMinutes := 0
	if riderLat != 0 && riderLng != 0 && targetLat != 0 && targetLng != 0 {
		distKm := h.geo.Distance(riderLat, riderLng, targetLat, targetLng)
		etaMinutes = h.geo.EstimateDeliveryTime(distKm, 0)
	}

	// Resolve rider display details once so the client can render the
	// tracking card without a second round-trip.
	riderName, riderPhone := "", ""
	if riderID != "" {
		riderName, riderPhone = h.resolveDeliveryPartnerDetails(riderID)
	}

	utils.Success(c, gin.H{
		"order_id":                 orderID,
		"status":                   status,
		"restaurant_lat":           restLat,
		"restaurant_lng":           restLng,
		"customer_lat":             custLat,
		"customer_lng":             custLng,
		"rider_id":                 riderID,
		"rider_name":               riderName,
		"rider_phone":              riderPhone,
		"rider_lat":                riderLat,
		"rider_lng":                riderLng,
		"eta_minutes":              etaMinutes,
		"estimated_delivery_min":   getFloat(order, "estimated_delivery_min"),
		"placed_at":                order["placed_at"],
		"picked_up_at":             order["picked_up_at"],
		"delivered_at":             order["delivered_at"],
	})
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

	// Enrich with customer name and phone from users collection
	if custID != "" {
		existingName, _ := order["customer_name"].(string)
		existingPhone, _ := order["customer_phone"].(string)
		if existingName == "" || existingPhone == "" {
			if user, uErr := h.appwrite.GetUser(custID); uErr == nil && user != nil {
				if existingName == "" {
					if name, _ := user["name"].(string); name != "" {
						order["customer_name"] = name
					}
				}
				if existingPhone == "" {
					if phone, _ := user["phone"].(string); phone != "" {
						order["customer_phone"] = phone
					}
				}
			}
		}
	}

	// Enrich with delivery partner name/phone (delivery_partners may not store
	// name/phone — fall back to users collection)
	if deliveryID != "" {
		existingDPName, _ := order["delivery_partner_name"].(string)
		existingDPPhone, _ := order["delivery_partner_phone"].(string)
		if existingDPName == "" || existingDPPhone == "" {
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

	// Batch-fetch user + delivery_partner docs to avoid N+1 lookups while
	// enriching the order list with denormalized name/phone. delivery_partners
	// collection does not store name/phone — users collection is the fallback.
	userIDSet := make(map[string]struct{})
	dpUserIDSet := make(map[string]struct{})
	for _, order := range result.Documents {
		if custID, _ := order["customer_id"].(string); custID != "" {
			existingName, _ := order["customer_name"].(string)
			existingPhone, _ := order["customer_phone"].(string)
			if existingName == "" || existingPhone == "" {
				userIDSet[custID] = struct{}{}
			}
		}
		if dpID, _ := order["delivery_partner_id"].(string); dpID != "" {
			existingDPName, _ := order["delivery_partner_name"].(string)
			existingDPPhone, _ := order["delivery_partner_phone"].(string)
			if existingDPName == "" || existingDPPhone == "" {
				dpUserIDSet[dpID] = struct{}{}
				userIDSet[dpID] = struct{}{} // users fallback source
			}
		}
	}

	userByID := make(map[string]map[string]interface{}, len(userIDSet))
	if len(userIDSet) > 0 {
		ids := make([]string, 0, len(userIDSet))
		for id := range userIDSet {
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
	dpByUserID := make(map[string]map[string]interface{}, len(dpUserIDSet))
	if len(dpUserIDSet) > 0 {
		ids := make([]string, 0, len(dpUserIDSet))
		for id := range dpUserIDSet {
			ids = append(ids, id)
		}
		if dpList, dpErr := h.appwrite.ListDeliveryPartnersByUserIDs(ids); dpErr == nil && dpList != nil {
			for _, dp := range dpList.Documents {
				if uid, _ := dp["user_id"].(string); uid != "" {
					dpByUserID[uid] = dp
				}
			}
		}
	}

	for _, order := range result.Documents {
		if custID, _ := order["customer_id"].(string); custID != "" {
			if user, ok := userByID[custID]; ok {
				if existing, _ := order["customer_name"].(string); existing == "" {
					if name, _ := user["name"].(string); name != "" {
						order["customer_name"] = name
					}
				}
				if existing, _ := order["customer_phone"].(string); existing == "" {
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
				var name, phone string
				if dp, ok := dpByUserID[dpID]; ok {
					name, _ = dp["name"].(string)
					phone, _ = dp["phone"].(string)
				}
				if name == "" || phone == "" {
					if user, ok := userByID[dpID]; ok {
						if name == "" {
							name, _ = user["name"].(string)
						}
						if phone == "" {
							phone, _ = user["phone"].(string)
						}
					}
				}
				if existingDPName == "" && name != "" {
					order["delivery_partner_name"] = name
				}
				if existingDPPhone == "" && phone != "" {
					order["delivery_partner_phone"] = phone
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

	// Clear Redis delivery state so the assigned rider doesn't stay in busy_riders
	// forever (CancelOrder used to leak entries, causing permanent lockout).
	// Mirror the multi-order bookkeeping from UpdateStatus cancellation path so
	// rider_order_count stays accurate and is_on_delivery gets cleared on the
	// rider's last active order.
	dpUserID, _ := order["delivery_partner_id"].(string)
	if h.redis != nil {
		rCtx := c.Request.Context()
		if dpUserID != "" {
			_ = h.redis.Del(rCtx, "pending_rider:"+dpUserID)
			_, _ = h.redis.HDel(rCtx, "rider_track:"+dpUserID, orderID)
			count, _ := h.redis.Decr(rCtx, "rider_order_count:"+dpUserID)
			_, _ = h.redis.SRem(rCtx, "rider_active_orders:"+dpUserID, orderID)
			if count < 0 {
				_ = h.redis.Set(rCtx, "rider_order_count:"+dpUserID, 0, 24*time.Hour)
				count = 0
			}
			if count < 5 {
				_, _ = h.redis.SRem(rCtx, "busy_riders", dpUserID)
			}
			if count == 0 {
				if dpResult, dpErr := h.appwrite.GetDeliveryPartner(dpUserID); dpErr == nil && dpResult != nil && dpResult.Total > 0 {
					dpDocID, _ := dpResult.Documents[0]["$id"].(string)
					_, _ = h.appwrite.UpdateDeliveryPartner(dpDocID, map[string]interface{}{
						"is_on_delivery": false,
					})
				}
			}
		}
		_ = h.redis.Del(rCtx, "pending_delivery:"+orderID)
		_ = h.redis.Del(rCtx, "rejected_riders:"+orderID)
		_ = h.redis.Del(rCtx, "delivery_lock:"+orderID)
	}

	// Broadcast cancellation via WebSocket to customer, restaurant owner, and
	// assigned rider. Previously only the customer was notified — restaurant
	// dashboard kept showing the cancelled order and the rider continued toward
	// pickup with no signal to stop.
	if h.broadcaster != nil {
		orderNumber, _ := order["order_number"].(string)
		h.broadcaster.BroadcastOrderUpdate(userID, orderID, models.OrderStatusCancelled, "Order cancelled by customer")
		if restID, _ := order["restaurant_id"].(string); restID != "" {
			if rest, rErr := h.appwrite.GetRestaurant(restID); rErr == nil && rest != nil {
				if ownerID, _ := rest["owner_id"].(string); ownerID != "" {
					h.broadcaster.BroadcastOrderUpdate(ownerID, orderID, models.OrderStatusCancelled, "Order "+orderNumber+" cancelled by customer")
				}
			}
		}
		if dpUserID != "" {
			h.broadcaster.BroadcastOrderUpdate(dpUserID, orderID, models.OrderStatusCancelled, "Order "+orderNumber+" cancelled by customer")
		}
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
	// Idempotent: if the order is already at the requested status, return
	// the existing document instead of erroring. Without this, a spam-clicked
	// button or an optimistic-update rollback loop fires hundreds of 400s.
	if currentStatus == req.Status {
		utils.Success(c, order)
		return
	}
	if err := h.orders.ValidateTransition(currentStatus, req.Status); err != nil {
		log.Printf("[order] UpdateStatus: invalid transition order=%s role=%s user=%s from=%q to=%q",
			orderID, role, userID, currentStatus, req.Status)
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
	case models.OrderStatusPreparing:
		updateData["preparing_at"] = now
	case models.OrderStatusReady:
		updateData["prepared_at"] = now
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

	// Clear Redis delivery state when order is cancelled.
	// Without this, the assigned rider stays in busy_riders forever.
	if req.Status == models.OrderStatusCancelled && h.redis != nil {
		rCtx := c.Request.Context()
		if dpUserID, _ := order["delivery_partner_id"].(string); dpUserID != "" {
			_ = h.redis.Del(rCtx, "pending_rider:"+dpUserID)
			// Remove from the tracking hash so UpdateLocation stops broadcasting
			// this rider's GPS to the cancelled order's customer.
			_, _ = h.redis.HDel(rCtx, "rider_track:"+dpUserID, orderID)
			// Decrement active order count (multi-order support)
			count, _ := h.redis.Decr(rCtx, "rider_order_count:"+dpUserID)
			_, _ = h.redis.SRem(rCtx, "rider_active_orders:"+dpUserID, orderID)
			if count < 0 {
				_ = h.redis.Set(rCtx, "rider_order_count:"+dpUserID, 0, 24*time.Hour)
				count = 0
			}
			// Remove from busy only when below max capacity
			if count < 5 {
				_, _ = h.redis.SRem(rCtx, "busy_riders", dpUserID)
			}
			// Only clear is_on_delivery if this is the rider's last active order
			// (check Redis count which was decremented above)
			if count == 0 {
				dpResult, dpErr := h.appwrite.GetDeliveryPartner(dpUserID)
				if dpErr == nil && dpResult != nil && dpResult.Total > 0 {
					dpDocID, _ := dpResult.Documents[0]["$id"].(string)
					_, _ = h.appwrite.UpdateDeliveryPartner(dpDocID, map[string]interface{}{
						"is_on_delivery": false,
					})
				}
			}
		}
		_ = h.redis.Del(rCtx, "pending_delivery:"+orderID)
		_ = h.redis.Del(rCtx, "rejected_riders:"+orderID)
		_ = h.redis.Del(rCtx, "delivery_lock:"+orderID)
	}

	// Trigger delivery matching immediately AFTER persisting status="ready"
	// so the matcher finds the order in Appwrite without a race condition.
	if req.Status == models.OrderStatusReady && h.matcherCallback != nil {
		go h.matcherCallback()
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
				updateFields := map[string]interface{}{
					"total_deliveries": int(currentDeliveries) + 1,
					"total_earnings":   currentEarnings + orderEarning,
				}
				// Only clear is_on_delivery when this is the last active order
				// (determined by Redis count checked after Decr below)
				_, _ = h.appwrite.UpdateDeliveryPartner(dpDocID, updateFields)
			}
			// Update Redis for multi-order support
			var deliveredOrderCount int64
			if h.redis != nil {
				rCtx := c.Request.Context()
				// Clear the rider_track hash entry so location pings stop being
				// broadcast to this order's customer.
				_, _ = h.redis.HDel(rCtx, "rider_track:"+dpUserID, orderID)
				// Decrement active order count
				count, _ := h.redis.Decr(rCtx, "rider_order_count:"+dpUserID)
				_, _ = h.redis.SRem(rCtx, "rider_active_orders:"+dpUserID, orderID)
				if count < 0 {
					_ = h.redis.Set(rCtx, "rider_order_count:"+dpUserID, 0, 24*time.Hour)
					count = 0
				}
				deliveredOrderCount = count
				// Remove from busy set only when below max capacity
				if count < 5 {
					_, _ = h.redis.SRem(rCtx, "busy_riders", dpUserID)
				}
			}
			// Clear is_on_delivery in Appwrite when all orders are done
			if deliveredOrderCount == 0 {
				dpResult2, dpErr2 := h.appwrite.GetDeliveryPartner(dpUserID)
				if dpErr2 == nil && dpResult2 != nil && dpResult2.Total > 0 {
					dpDocID2, _ := dpResult2.Documents[0]["$id"].(string)
					_, _ = h.appwrite.UpdateDeliveryPartner(dpDocID2, map[string]interface{}{
						"is_on_delivery": false,
					})
				}
			}
		}
		// Immediately trigger matcher so the now-available rider gets the
		// next pending order without waiting for the 15s ticker.
		if h.matcherCallback != nil {
			go h.matcherCallback()
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
			notifBody = "Your order " + orderNumber + " has been delivered. Enjoy your meal! Tap to rate your order."
		case models.OrderStatusCancelled:
			notifTitle = "Order Cancelled"
			notifBody = "Your order " + orderNumber + " was cancelled by the restaurant"
			if req.Reason != "" {
				notifBody += ": " + req.Reason
			}
		}
		if notifTitle != "" {
			notifData := map[string]interface{}{"order_id": orderID, "status": req.Status}
			// Deep-link customers straight into the review screen on delivery
			// so they don't have to hunt through past orders to leave a review.
			if req.Status == models.OrderStatusDelivered {
				notifData["deep_link"] = "/review/" + orderID
			}
			_, _ = h.appwrite.CreateNotification("unique()", map[string]interface{}{
				"user_id": customerID,
				"title":   notifTitle,
				"body":    notifBody,
				"type":    "order_status",
				"data":    notifData,
				"is_read": false,
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
