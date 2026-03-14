package handlers_test

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/chizze/backend/internal/testutil"
)

// ─── Seed helpers ───

// seedOrderData sets up the common data needed for placing an order.
func seedOrderData(te *testutil.TestEnv) {
	te.T.Helper()
	te.SeedUser("cust_1", map[string]interface{}{
		"phone": "+919876543210",
		"name":  "Test Customer",
		"role":  "customer",
	})
	te.SeedUser("owner_1", map[string]interface{}{
		"phone": "+919876543211",
		"name":  "Restaurant Owner",
		"role":  "restaurant_owner",
	})
	te.SeedRestaurant("rest_1", "owner_1", 12.97, 77.59, true)
	te.SeedMenuItem("item_1", "rest_1", 200.0)
	te.SeedMenuItem("item_2", "rest_1", 150.0)
	te.SeedAddress("addr_1", "cust_1", 12.98, 77.60)
}

func placeOrderBody() map[string]interface{} {
	return map[string]interface{}{
		"restaurant_id":       "rest_1",
		"delivery_address_id": "addr_1",
		"items": []map[string]interface{}{
			{"item_id": "item_1", "name": "Test Item item_1", "quantity": 2, "price": 200.0},
			{"item_id": "item_2", "name": "Test Item item_2", "quantity": 1, "price": 150.0},
		},
		"payment_method": "cod",
		"delivery_type":  "standard",
	}
}

// ─── PlaceOrder ───

func TestPlaceOrder_Success(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()
	seedOrderData(te)

	rec := te.AuthRequest("POST", "/api/v1/orders", placeOrderBody(), "cust_1", "customer")

	if rec.Code != 201 {
		t.Fatalf("expected 201, got %d: %s", rec.Code, rec.Body.String())
	}

	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})

	// Check order number format
	orderNum, _ := data["order_number"].(string)
	if !strings.HasPrefix(orderNum, "CHZ-") {
		t.Errorf("expected order_number to start with CHZ-, got %v", orderNum)
	}

	if data["status"] != "placed" {
		t.Errorf("expected status=placed, got %v", data["status"])
	}
	if data["payment_status"] != "pending" {
		t.Errorf("expected payment_status=pending, got %v", data["payment_status"])
	}

	// Verify server-side price: 200*2 + 150*1 = 550
	itemTotal, _ := data["item_total"].(float64)
	if itemTotal != 550.0 {
		t.Errorf("expected item_total=550, got %v", itemTotal)
	}

	// Platform fee should be 5.0
	platformFee, _ := data["platform_fee"].(float64)
	if platformFee != 5.0 {
		t.Errorf("expected platform_fee=5, got %v", platformFee)
	}

	// GST should be 5% of item total = 27.5
	gst, _ := data["gst"].(float64)
	if gst != 27.5 {
		t.Errorf("expected gst=27.5, got %v", gst)
	}

	// Delivery is free for orders > 299 (standard)
	deliveryFee, _ := data["delivery_fee"].(float64)
	if deliveryFee != 0 {
		t.Errorf("expected delivery_fee=0 (free above 299), got %v", deliveryFee)
	}

	// Verify order was created in the store
	if te.FakeAW.DocumentCount("orders") != 1 {
		t.Errorf("expected 1 order document, got %d", te.FakeAW.DocumentCount("orders"))
	}
}

func TestPlaceOrder_RestaurantOffline(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("cust_1", map[string]interface{}{"phone": "+919876543210", "role": "customer"})
	te.SeedRestaurant("rest_1", "owner_1", 12.97, 77.59, false) // offline
	te.SeedMenuItem("item_1", "rest_1", 200.0)
	te.SeedAddress("addr_1", "cust_1", 12.98, 77.60)

	rec := te.AuthRequest("POST", "/api/v1/orders", placeOrderBody(), "cust_1", "customer")

	if rec.Code != 400 {
		t.Fatalf("expected 400 for offline restaurant, got %d: %s", rec.Code, rec.Body.String())
	}
	resp := te.ParseResponse(rec)
	if !strings.Contains(resp["error"].(string), "offline") {
		t.Errorf("expected error about offline, got %v", resp["error"])
	}
}

func TestPlaceOrder_AddressNotOwned(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("cust_1", map[string]interface{}{"phone": "+919876543210", "role": "customer"})
	te.SeedRestaurant("rest_1", "owner_1", 12.97, 77.59, true)
	te.SeedMenuItem("item_1", "rest_1", 200.0)
	te.SeedMenuItem("item_2", "rest_1", 150.0)
	te.SeedAddress("addr_1", "other_user", 12.98, 77.60) // owned by different user

	rec := te.AuthRequest("POST", "/api/v1/orders", placeOrderBody(), "cust_1", "customer")

	if rec.Code != 403 {
		t.Fatalf("expected 403 for wrong address owner, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestPlaceOrder_TooFar(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("cust_1", map[string]interface{}{"phone": "+919876543210", "role": "customer"})
	te.SeedRestaurant("rest_1", "owner_1", 12.97, 77.59, true) // Bangalore
	te.SeedMenuItem("item_1", "rest_1", 200.0)
	te.SeedMenuItem("item_2", "rest_1", 150.0)
	te.SeedAddress("addr_1", "cust_1", 19.07, 72.87) // Mumbai ~840km away

	rec := te.AuthRequest("POST", "/api/v1/orders", placeOrderBody(), "cust_1", "customer")

	if rec.Code != 400 {
		t.Fatalf("expected 400 for too far, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestPlaceOrder_InvalidPaymentMethod(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()
	seedOrderData(te)

	body := placeOrderBody()
	body["payment_method"] = "bitcoin"

	rec := te.AuthRequest("POST", "/api/v1/orders", body, "cust_1", "customer")

	if rec.Code != 400 {
		t.Fatalf("expected 400 for invalid payment, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestPlaceOrder_RazorpayNormalized(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()
	seedOrderData(te)

	body := placeOrderBody()
	body["payment_method"] = "razorpay"

	rec := te.AuthRequest("POST", "/api/v1/orders", body, "cust_1", "customer")

	if rec.Code != 201 {
		t.Fatalf("expected 201, got %d: %s", rec.Code, rec.Body.String())
	}

	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})
	if data["payment_method"] != "online" {
		t.Errorf("expected payment_method=online (razorpay normalized), got %v", data["payment_method"])
	}
}

func TestPlaceOrder_ItemUnavailable(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("cust_1", map[string]interface{}{"phone": "+919876543210", "role": "customer"})
	te.SeedRestaurant("rest_1", "owner_1", 12.97, 77.59, true)
	// item_1 marked unavailable
	te.FakeAW.SeedDocument("menu_items", "item_1", map[string]interface{}{
		"restaurant_id": "rest_1", "name": "Unavailable Item", "price": 200.0,
		"is_available": false, "is_veg": true,
	})
	te.SeedMenuItem("item_2", "rest_1", 150.0)
	te.SeedAddress("addr_1", "cust_1", 12.98, 77.60)

	rec := te.AuthRequest("POST", "/api/v1/orders", placeOrderBody(), "cust_1", "customer")

	if rec.Code != 400 {
		t.Fatalf("expected 400 for unavailable item, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestPlaceOrder_IdempotencyKey(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()
	seedOrderData(te)

	body := placeOrderBody()
	bodyJSON, _ := json.Marshal(body)

	// First request with idempotency key
	req1 := te.MakeRequest("POST", "/api/v1/orders", bodyJSON, "cust_1", "customer")
	req1.Header.Set("X-Idempotency-Key", "idem-123")
	rec1 := te.ServeRequest(req1)
	if rec1.Code != 201 {
		t.Fatalf("first request: expected 201, got %d: %s", rec1.Code, rec1.Body.String())
	}

	// Second request with same key — should return cached response
	req2 := te.MakeRequest("POST", "/api/v1/orders", bodyJSON, "cust_1", "customer")
	req2.Header.Set("X-Idempotency-Key", "idem-123")
	rec2 := te.ServeRequest(req2)
	if rec2.Code != 201 {
		t.Fatalf("second request: expected 201, got %d: %s", rec2.Code, rec2.Body.String())
	}

	// Only 1 order should exist
	if te.FakeAW.DocumentCount("orders") != 1 {
		t.Errorf("expected 1 order (idempotent), got %d", te.FakeAW.DocumentCount("orders"))
	}
}

func TestPlaceOrder_NoAuth(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	rec := te.Request("POST", "/api/v1/orders", placeOrderBody())
	if rec.Code != 401 {
		t.Fatalf("expected 401 for unauthenticated, got %d", rec.Code)
	}
}

func TestPlaceOrder_EmptyItems(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()
	seedOrderData(te)

	body := placeOrderBody()
	body["items"] = []map[string]interface{}{}

	rec := te.AuthRequest("POST", "/api/v1/orders", body, "cust_1", "customer")
	if rec.Code != 400 {
		t.Fatalf("expected 400 for empty items, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestPlaceOrder_MissingRestaurantID(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()
	seedOrderData(te)

	body := placeOrderBody()
	delete(body, "restaurant_id")

	rec := te.AuthRequest("POST", "/api/v1/orders", body, "cust_1", "customer")
	if rec.Code != 400 {
		t.Fatalf("expected 400 for missing restaurant_id, got %d", rec.Code)
	}
}

func TestPlaceOrder_NonexistentRestaurant(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()
	seedOrderData(te)

	body := placeOrderBody()
	body["restaurant_id"] = "nonexistent_restaurant"

	rec := te.AuthRequest("POST", "/api/v1/orders", body, "cust_1", "customer")
	if rec.Code != 400 {
		t.Fatalf("expected 400 for nonexistent restaurant, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestPlaceOrder_NonexistentAddress(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()
	seedOrderData(te)

	body := placeOrderBody()
	body["delivery_address_id"] = "addr_nonexistent"

	rec := te.AuthRequest("POST", "/api/v1/orders", body, "cust_1", "customer")
	if rec.Code != 400 {
		t.Fatalf("expected 400 for nonexistent address, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestPlaceOrder_WrongRestaurantItem(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()
	seedOrderData(te)

	// Menu item from different restaurant
	te.SeedMenuItem("item_other", "rest_other", 100.0)

	body := placeOrderBody()
	body["items"] = []map[string]interface{}{
		{"item_id": "item_other", "name": "Other", "quantity": 1, "price": 100.0},
	}

	rec := te.AuthRequest("POST", "/api/v1/orders", body, "cust_1", "customer")
	if rec.Code != 400 {
		t.Fatalf("expected 400 for item from wrong restaurant, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestPlaceOrder_NegativeTipClampedToZero(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()
	seedOrderData(te)

	body := placeOrderBody()
	body["tip"] = -50.0

	rec := te.AuthRequest("POST", "/api/v1/orders", body, "cust_1", "customer")
	if rec.Code != 201 {
		t.Fatalf("expected 201, got %d: %s", rec.Code, rec.Body.String())
	}
	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})
	tip, _ := data["tip"].(float64)
	if tip != 0 {
		t.Errorf("expected tip=0 (clamped from negative), got %v", tip)
	}
}

func TestPlaceOrder_PositiveTip(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()
	seedOrderData(te)

	body := placeOrderBody()
	body["tip"] = 25.0

	rec := te.AuthRequest("POST", "/api/v1/orders", body, "cust_1", "customer")
	if rec.Code != 201 {
		t.Fatalf("expected 201, got %d: %s", rec.Code, rec.Body.String())
	}
	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})
	tip, _ := data["tip"].(float64)
	if tip != 25.0 {
		t.Errorf("expected tip=25, got %v", tip)
	}
}

func TestPlaceOrder_EcoDeliveryType(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("cust_1", map[string]interface{}{"phone": "+919876543210", "role": "customer"})
	te.SeedRestaurant("rest_1", "owner_1", 12.97, 77.59, true)
	// Small order under free delivery threshold with eco mode
	te.SeedMenuItem("item_cheap", "rest_1", 100.0)
	te.SeedAddress("addr_1", "cust_1", 12.98, 77.60)

	body := map[string]interface{}{
		"restaurant_id":       "rest_1",
		"delivery_address_id": "addr_1",
		"items": []map[string]interface{}{
			{"item_id": "item_cheap", "name": "Cheap", "quantity": 1, "price": 100.0},
		},
		"payment_method": "cod",
		"delivery_type":  "eco",
	}

	rec := te.AuthRequest("POST", "/api/v1/orders", body, "cust_1", "customer")
	if rec.Code != 201 {
		t.Fatalf("expected 201, got %d: %s", rec.Code, rec.Body.String())
	}
	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})
	if data["delivery_type"] != "eco" {
		t.Errorf("expected delivery_type=eco, got %v", data["delivery_type"])
	}
}

func TestPlaceOrder_UnknownDeliveryTypeNormalized(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()
	seedOrderData(te)

	body := placeOrderBody()
	body["delivery_type"] = "premium"

	rec := te.AuthRequest("POST", "/api/v1/orders", body, "cust_1", "customer")
	if rec.Code != 201 {
		t.Fatalf("expected 201, got %d: %s", rec.Code, rec.Body.String())
	}
	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})
	if data["delivery_type"] != "standard" {
		t.Errorf("expected delivery_type=standard (normalized from premium), got %v", data["delivery_type"])
	}
}

func TestPlaceOrder_AllPaymentMethods(t *testing.T) {
	validMethods := []string{"cod", "upi", "card", "wallet", "netbanking", "online"}
	for _, method := range validMethods {
		t.Run(method, func(t *testing.T) {
			te := testutil.NewTestEnv(t)
			defer te.Close()
			seedOrderData(te)

			body := placeOrderBody()
			body["payment_method"] = method

			rec := te.AuthRequest("POST", "/api/v1/orders", body, "cust_1", "customer")
			if rec.Code != 201 {
				t.Fatalf("payment method %s: expected 201, got %d: %s", method, rec.Code, rec.Body.String())
			}
		})
	}
}

func TestPlaceOrder_WithCoupon(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()
	seedOrderData(te)

	now := time.Now()
	te.SeedCoupon("SAVE50", map[string]interface{}{
		"code":            "SAVE50",
		"discount_type":   "percentage",
		"discount_value":  10.0,
		"min_order_value": 100.0,
		"max_discount":    50.0,
		"usage_limit":     100.0,
		"used_count":      0.0,
		"is_active":       true,
		"valid_from":      now.Add(-24 * time.Hour).Format(time.RFC3339),
		"valid_until":     now.Add(24 * time.Hour).Format(time.RFC3339),
	})

	body := placeOrderBody()
	body["coupon_code"] = "SAVE50"

	rec := te.AuthRequest("POST", "/api/v1/orders", body, "cust_1", "customer")
	if rec.Code != 201 {
		t.Fatalf("expected 201, got %d: %s", rec.Code, rec.Body.String())
	}
	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})

	discount, _ := data["discount"].(float64)
	if discount <= 0 {
		t.Errorf("expected positive discount, got %v", discount)
	}
	if discount > 50.0 {
		t.Errorf("expected discount <= max_discount 50, got %v", discount)
	}
}

func TestPlaceOrder_InvalidCouponIgnored(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()
	seedOrderData(te)

	body := placeOrderBody()
	body["coupon_code"] = "FAKECOUPON"

	rec := te.AuthRequest("POST", "/api/v1/orders", body, "cust_1", "customer")
	if rec.Code != 201 {
		t.Fatalf("expected 201 (invalid coupon should be ignored), got %d: %s", rec.Code, rec.Body.String())
	}
	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})
	discount, _ := data["discount"].(float64)
	if discount != 0 {
		t.Errorf("expected discount=0 for invalid coupon, got %v", discount)
	}
}

func TestPlaceOrder_SpecialInstructions(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()
	seedOrderData(te)

	body := placeOrderBody()
	body["special_instructions"] = "Extra spicy please"
	body["delivery_instructions"] = "Ring the bell twice"

	rec := te.AuthRequest("POST", "/api/v1/orders", body, "cust_1", "customer")
	if rec.Code != 201 {
		t.Fatalf("expected 201, got %d", rec.Code)
	}
	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})

	if data["special_instructions"] != "Extra spicy please" {
		t.Errorf("expected special_instructions to be preserved")
	}
	if data["delivery_instructions"] != "Ring the bell twice" {
		t.Errorf("expected delivery_instructions to be preserved")
	}
}

func TestPlaceOrder_DifferentIdempotencyKeysDifferentOrders(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()
	seedOrderData(te)

	body := placeOrderBody()
	bodyJSON, _ := json.Marshal(body)

	req1 := te.MakeRequest("POST", "/api/v1/orders", bodyJSON, "cust_1", "customer")
	req1.Header.Set("X-Idempotency-Key", "key-A")
	rec1 := te.ServeRequest(req1)
	if rec1.Code != 201 {
		t.Fatalf("first: expected 201, got %d", rec1.Code)
	}

	req2 := te.MakeRequest("POST", "/api/v1/orders", bodyJSON, "cust_1", "customer")
	req2.Header.Set("X-Idempotency-Key", "key-B")
	rec2 := te.ServeRequest(req2)
	if rec2.Code != 201 {
		t.Fatalf("second: expected 201, got %d", rec2.Code)
	}

	if te.FakeAW.DocumentCount("orders") != 2 {
		t.Errorf("expected 2 orders for different idempotency keys, got %d", te.FakeAW.DocumentCount("orders"))
	}
}

// ─── UpdateStatus Lifecycle ───

func TestUpdateStatus_FullLifecycle(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()
	seedOrderData(te)

	// Place order
	rec := te.AuthRequest("POST", "/api/v1/orders", placeOrderBody(), "cust_1", "customer")
	if rec.Code != 201 {
		t.Fatalf("PlaceOrder: expected 201, got %d: %s", rec.Code, rec.Body.String())
	}
	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})
	orderID, _ := data["$id"].(string)

	// Step through statuses as restaurant owner
	ownerStatuses := []struct {
		status    string
		expectKey string
	}{
		{"confirmed", "confirmed_at"},
		{"preparing", ""},
		{"ready", "prepared_at"},
	}

	for _, s := range ownerStatuses {
		rec = te.AuthRequest("PUT", "/api/v1/partner/orders/"+orderID+"/status",
			map[string]interface{}{"status": s.status}, "owner_1", "restaurant_owner")
		if rec.Code != 200 {
			t.Fatalf("UpdateStatus(%s): expected 200, got %d: %s", s.status, rec.Code, rec.Body.String())
		}
		// Verify in fake store
		doc := te.FakeAW.GetDocument("orders", orderID)
		if doc["status"] != s.status {
			t.Errorf("expected status=%s, got %v", s.status, doc["status"])
		}
		if s.expectKey != "" && (doc[s.expectKey] == nil || doc[s.expectKey] == "") {
			t.Errorf("expected %s to be set for status %s", s.expectKey, s.status)
		}
	}

	// Verify matcherCallback was triggered on "ready"
	if !te.MatcherCalled {
		t.Error("expected matcherCallback to fire when order became ready")
	}

	// Assign delivery partner to the order so they can update status
	dpUserID := "dp_user_1"
	te.SeedUser(dpUserID, map[string]interface{}{
		"phone": "+919876543212", "name": "Rider One", "role": "delivery_partner",
	})
	te.SeedDeliveryPartner("dp_1", dpUserID, true, 12.97, 77.59)

	// Manually assign delivery partner
	te.FakeAW.SeedDocument("orders", orderID, func() map[string]interface{} {
		doc := te.FakeAW.GetDocument("orders", orderID)
		doc["delivery_partner_id"] = dpUserID
		doc["delivery_partner_name"] = "Rider One"
		doc["delivery_partner_phone"] = "+919876543212"
		return doc
	}())

	// Delivery partner status updates
	dpStatuses := []struct {
		status    string
		expectKey string
	}{
		{"pickedUp", "picked_up_at"},
		{"outForDelivery", ""},
		{"delivered", "delivered_at"},
	}

	for _, s := range dpStatuses {
		rec = te.AuthRequest("PUT", "/api/v1/delivery/orders/"+orderID+"/status",
			map[string]interface{}{"status": s.status}, dpUserID, "delivery_partner")
		if rec.Code != 200 {
			t.Fatalf("UpdateStatus(%s): expected 200, got %d: %s", s.status, rec.Code, rec.Body.String())
		}
		doc := te.FakeAW.GetDocument("orders", orderID)
		if doc["status"] != s.status {
			t.Errorf("expected status=%s, got %v", s.status, doc["status"])
		}
		if s.expectKey != "" && (doc[s.expectKey] == nil || doc[s.expectKey] == "") {
			t.Errorf("expected %s to be set for status %s", s.expectKey, s.status)
		}
	}

	// Verify COD order marked as paid
	finalDoc := te.FakeAW.GetDocument("orders", orderID)
	if finalDoc["payment_status"] != "paid" {
		t.Errorf("expected payment_status=paid for COD delivered order, got %v", finalDoc["payment_status"])
	}

	// Verify notification was created for customer
	if te.FakeAW.DocumentCount("notifications") == 0 {
		t.Error("expected notifications to be created during status updates")
	}
}

func TestUpdateStatus_InvalidTransition(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()
	seedOrderData(te)

	te.SeedOrder("order_placed", map[string]interface{}{
		"customer_id":   "cust_1",
		"restaurant_id": "rest_1",
		"status":        "placed",
		"order_number":  "CHZ-001",
	})

	// Try to jump from placed → ready (invalid)
	rec := te.AuthRequest("PUT", "/api/v1/partner/orders/order_placed/status",
		map[string]interface{}{"status": "ready"}, "owner_1", "restaurant_owner")

	if rec.Code != 400 {
		t.Fatalf("expected 400 for invalid transition, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestUpdateStatus_WrongRole(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()
	seedOrderData(te)

	te.SeedOrder("order_test", map[string]interface{}{
		"customer_id":   "cust_1",
		"restaurant_id": "rest_1",
		"status":        "placed",
		"order_number":  "CHZ-002",
	})

	// Customer trying to update status — should get 403 from RequireRole middleware
	rec := te.AuthRequest("PUT", "/api/v1/partner/orders/order_test/status",
		map[string]interface{}{"status": "confirmed"}, "cust_1", "customer")
	if rec.Code != 403 {
		t.Fatalf("expected 403 for customer updating status, got %d", rec.Code)
	}
}

func TestUpdateStatus_WrongRestaurant(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()
	seedOrderData(te)

	te.SeedUser("owner_2", map[string]interface{}{
		"phone": "+919876543299", "role": "restaurant_owner",
	})
	te.SeedRestaurant("rest_2", "owner_2", 12.97, 77.59, true)

	te.SeedOrder("order_other_rest", map[string]interface{}{
		"customer_id":   "cust_1",
		"restaurant_id": "rest_2", // belongs to owner_2
		"status":        "placed",
		"order_number":  "CHZ-020",
	})

	// owner_1 trying to update order from rest_2
	rec := te.AuthRequest("PUT", "/api/v1/partner/orders/order_other_rest/status",
		map[string]interface{}{"status": "confirmed"}, "owner_1", "restaurant_owner")
	if rec.Code != 403 {
		t.Fatalf("expected 403 for wrong restaurant, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestUpdateStatus_DPNotAssigned(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()
	seedOrderData(te)

	te.SeedUser("dp_unassigned", map[string]interface{}{"phone": "+919876543250", "role": "delivery_partner"})
	te.SeedDeliveryPartner("dp_ua", "dp_unassigned", true, 12.97, 77.59)
	te.SeedOrder("order_dp_check", map[string]interface{}{
		"customer_id":         "cust_1",
		"restaurant_id":       "rest_1",
		"delivery_partner_id": "other_dp",
		"status":              "ready",
		"order_number":        "CHZ-021",
	})

	rec := te.AuthRequest("PUT", "/api/v1/delivery/orders/order_dp_check/status",
		map[string]interface{}{"status": "pickedUp"}, "dp_unassigned", "delivery_partner")
	if rec.Code != 403 {
		t.Fatalf("expected 403 for unassigned DP, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestUpdateStatus_RestaurantInvalidStatuses(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()
	seedOrderData(te)

	te.SeedOrder("order_rest_inv", map[string]interface{}{
		"customer_id":   "cust_1",
		"restaurant_id": "rest_1",
		"status":        "ready",
		"order_number":  "CHZ-022",
	})

	// Restaurant owner trying to set pickedUp (not allowed for restaurant role)
	rec := te.AuthRequest("PUT", "/api/v1/partner/orders/order_rest_inv/status",
		map[string]interface{}{"status": "pickedUp"}, "owner_1", "restaurant_owner")
	if rec.Code != 403 {
		t.Fatalf("expected 403 for restaurant setting pickedUp, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestUpdateStatus_NonexistentOrder(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()
	seedOrderData(te)

	rec := te.AuthRequest("PUT", "/api/v1/partner/orders/nonexistent_order/status",
		map[string]interface{}{"status": "confirmed"}, "owner_1", "restaurant_owner")
	if rec.Code != 404 {
		t.Fatalf("expected 404, got %d", rec.Code)
	}
}

func TestUpdateStatus_MissingStatusField(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()
	seedOrderData(te)

	te.SeedOrder("order_no_status", map[string]interface{}{
		"customer_id":   "cust_1",
		"restaurant_id": "rest_1",
		"status":        "placed",
		"order_number":  "CHZ-023",
	})

	rec := te.AuthRequest("PUT", "/api/v1/partner/orders/order_no_status/status",
		map[string]interface{}{}, "owner_1", "restaurant_owner")
	if rec.Code != 400 {
		t.Fatalf("expected 400 for missing status, got %d", rec.Code)
	}
}

// ─── CancelOrder ───

func TestCancelOrder_Success(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("cust_1", map[string]interface{}{"phone": "+919876543210", "role": "customer"})
	te.SeedOrder("order_cancel", map[string]interface{}{
		"customer_id":   "cust_1",
		"restaurant_id": "rest_1",
		"status":        "placed",
		"order_number":  "CHZ-003",
	})

	rec := te.AuthRequest("PUT", "/api/v1/orders/order_cancel/cancel",
		map[string]interface{}{"reason": "Changed my mind"}, "cust_1", "customer")

	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	doc := te.FakeAW.GetDocument("orders", "order_cancel")
	if doc["status"] != "cancelled" {
		t.Errorf("expected status=cancelled, got %v", doc["status"])
	}
	if doc["cancelled_by"] != "customer" {
		t.Errorf("expected cancelled_by=customer, got %v", doc["cancelled_by"])
	}
	if doc["cancellation_reason"] != "Changed my mind" {
		t.Errorf("expected cancellation_reason to match, got %v", doc["cancellation_reason"])
	}
}

func TestCancelOrder_NotOwner(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("cust_1", map[string]interface{}{"phone": "+919876543210", "role": "customer"})
	te.SeedOrder("order_notmine", map[string]interface{}{
		"customer_id":   "other_cust",
		"restaurant_id": "rest_1",
		"status":        "placed",
		"order_number":  "CHZ-004",
	})

	rec := te.AuthRequest("PUT", "/api/v1/orders/order_notmine/cancel",
		map[string]interface{}{"reason": "test"}, "cust_1", "customer")

	if rec.Code != 403 {
		t.Fatalf("expected 403, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestCancelOrder_DeliveredOrder(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("cust_1", map[string]interface{}{"phone": "+919876543210", "role": "customer"})
	te.SeedOrder("order_delivered", map[string]interface{}{
		"customer_id":   "cust_1",
		"restaurant_id": "rest_1",
		"status":        "delivered",
		"order_number":  "CHZ-005",
	})

	rec := te.AuthRequest("PUT", "/api/v1/orders/order_delivered/cancel",
		map[string]interface{}{"reason": "too late"}, "cust_1", "customer")

	if rec.Code != 400 {
		t.Fatalf("expected 400 for invalid transition, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestCancelOrder_MissingReason(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("cust_1", map[string]interface{}{"phone": "+919876543210", "role": "customer"})
	te.SeedOrder("order_mr", map[string]interface{}{
		"customer_id":   "cust_1",
		"restaurant_id": "rest_1",
		"status":        "placed",
		"order_number":  "CHZ-024",
	})

	rec := te.AuthRequest("PUT", "/api/v1/orders/order_mr/cancel",
		map[string]interface{}{}, "cust_1", "customer")
	if rec.Code != 400 {
		t.Fatalf("expected 400 for missing reason, got %d", rec.Code)
	}
}

func TestCancelOrder_FromEachAllowedStatus(t *testing.T) {
	statuses := []string{"placed", "confirmed", "preparing"}
	for _, s := range statuses {
		t.Run("cancel_from_"+s, func(t *testing.T) {
			te := testutil.NewTestEnv(t)
			defer te.Close()

			te.SeedUser("cust_1", map[string]interface{}{"phone": "+919876543210", "role": "customer"})
			te.SeedOrder("order_cs", map[string]interface{}{
				"customer_id":   "cust_1",
				"restaurant_id": "rest_1",
				"status":        s,
				"order_number":  "CHZ-CS",
			})

			rec := te.AuthRequest("PUT", "/api/v1/orders/order_cs/cancel",
				map[string]interface{}{"reason": "test"}, "cust_1", "customer")
			if rec.Code != 200 {
				t.Fatalf("expected 200 cancelling from %s, got %d: %s", s, rec.Code, rec.Body.String())
			}
		})
	}
}

func TestCancelOrder_FromNonCancellableStatuses(t *testing.T) {
	statuses := []string{"ready", "pickedUp", "outForDelivery", "delivered"}
	for _, s := range statuses {
		t.Run("no_cancel_from_"+s, func(t *testing.T) {
			te := testutil.NewTestEnv(t)
			defer te.Close()

			te.SeedUser("cust_1", map[string]interface{}{"phone": "+919876543210", "role": "customer"})
			te.SeedOrder("order_nc", map[string]interface{}{
				"customer_id":   "cust_1",
				"restaurant_id": "rest_1",
				"status":        s,
				"order_number":  "CHZ-NC",
			})

			rec := te.AuthRequest("PUT", "/api/v1/orders/order_nc/cancel",
				map[string]interface{}{"reason": "test"}, "cust_1", "customer")
			if rec.Code != 400 {
				t.Fatalf("expected 400 cancelling from %s, got %d", s, rec.Code)
			}
		})
	}
}

// ─── GetOrder ownership ───

func TestGetOrder_OwnershipCheck(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("cust_1", map[string]interface{}{"phone": "+919876543210", "name": "Customer", "role": "customer"})
	te.SeedUser("owner_1", map[string]interface{}{"phone": "+919876543211", "name": "Owner", "role": "restaurant_owner"})
	te.SeedRestaurant("rest_1", "owner_1", 12.97, 77.59, true)
	te.SeedOrder("order_own", map[string]interface{}{
		"customer_id":         "cust_1",
		"restaurant_id":       "rest_1",
		"delivery_partner_id": "dp_user_1",
		"status":              "placed",
		"order_number":        "CHZ-006",
	})

	// Customer can see their own order
	rec := te.AuthRequest("GET", "/api/v1/orders/order_own", nil, "cust_1", "customer")
	if rec.Code != 200 {
		t.Fatalf("customer should see own order, got %d", rec.Code)
	}

	// Different customer cannot
	rec = te.AuthRequest("GET", "/api/v1/orders/order_own", nil, "cust_other", "customer")
	if rec.Code != 403 {
		t.Fatalf("different customer should get 403, got %d", rec.Code)
	}

	// Restaurant owner of the order's restaurant can see it
	rec = te.AuthRequest("GET", "/api/v1/orders/order_own", nil, "owner_1", "restaurant_owner")
	if rec.Code != 200 {
		t.Fatalf("restaurant owner should see their restaurant's order, got %d", rec.Code)
	}

	// Assigned delivery partner can see it
	te.SeedUser("dp_user_1", map[string]interface{}{"phone": "+919876543213", "role": "delivery_partner"})
	rec = te.AuthRequest("GET", "/api/v1/orders/order_own", nil, "dp_user_1", "delivery_partner")
	if rec.Code != 200 {
		t.Fatalf("assigned delivery partner should see order, got %d", rec.Code)
	}

	// Unassigned delivery partner cannot
	te.SeedUser("dp_other", map[string]interface{}{"phone": "+919876543214", "role": "delivery_partner"})
	rec = te.AuthRequest("GET", "/api/v1/orders/order_own", nil, "dp_other", "delivery_partner")
	if rec.Code != 403 {
		t.Fatalf("unassigned DP should get 403, got %d", rec.Code)
	}
}

func TestGetOrder_NotFound(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	rec := te.AuthRequest("GET", "/api/v1/orders/nonexistent", nil, "cust_1", "customer")
	if rec.Code != 404 {
		t.Fatalf("expected 404, got %d", rec.Code)
	}
}

func TestGetOrder_EnrichesCustomerName(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("cust_enrich", map[string]interface{}{
		"phone": "+919876543210", "name": "Rich Name", "role": "customer",
	})
	te.SeedOrder("order_enrich", map[string]interface{}{
		"customer_id":   "cust_enrich",
		"restaurant_id": "r1",
		"status":        "placed",
		"order_number":  "CHZ-025",
	})

	rec := te.AuthRequest("GET", "/api/v1/orders/order_enrich", nil, "cust_enrich", "customer")
	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})
	if data["customer_name"] != "Rich Name" {
		t.Errorf("expected customer_name=Rich Name, got %v", data["customer_name"])
	}
}

// ─── ListOrders ───

func TestListOrders_CustomerSeesOwnOrders(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("cust_list", map[string]interface{}{"phone": "+919876543210", "name": "C", "role": "customer"})
	te.SeedOrder("order_l1", map[string]interface{}{
		"customer_id": "cust_list", "restaurant_id": "r1",
		"status": "placed", "order_number": "CHZ-L1", "placed_at": time.Now().Format(time.RFC3339),
	})
	te.SeedOrder("order_l2", map[string]interface{}{
		"customer_id": "other_cust", "restaurant_id": "r1",
		"status": "placed", "order_number": "CHZ-L2", "placed_at": time.Now().Format(time.RFC3339),
	})

	rec := te.AuthRequest("GET", "/api/v1/orders", nil, "cust_list", "customer")
	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	resp := te.ParseResponse(rec)
	orders, _ := resp["data"].([]interface{})
	if len(orders) != 1 {
		t.Errorf("expected 1 order for this customer, got %d", len(orders))
	}
}

func TestListOrders_StatusFilter(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("cust_sf", map[string]interface{}{"phone": "+919876543210", "role": "customer"})
	te.SeedOrder("order_sf1", map[string]interface{}{
		"customer_id": "cust_sf", "restaurant_id": "r1",
		"status": "placed", "order_number": "CHZ-SF1", "placed_at": time.Now().Format(time.RFC3339),
	})
	te.SeedOrder("order_sf2", map[string]interface{}{
		"customer_id": "cust_sf", "restaurant_id": "r1",
		"status": "delivered", "order_number": "CHZ-SF2", "placed_at": time.Now().Format(time.RFC3339),
	})

	rec := te.AuthRequest("GET", "/api/v1/orders?status=delivered", nil, "cust_sf", "customer")
	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	resp := te.ParseResponse(rec)
	orders, _ := resp["data"].([]interface{})
	if len(orders) != 1 {
		t.Errorf("expected 1 delivered order, got %d", len(orders))
	}
}

func TestListOrders_RestaurantOwnerSeesTheirOrders(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("owner_lo", map[string]interface{}{"phone": "+919876543211", "role": "restaurant_owner"})
	te.SeedRestaurant("rest_lo", "owner_lo", 12.97, 77.59, true)
	te.SeedOrder("order_lo1", map[string]interface{}{
		"customer_id": "c1", "restaurant_id": "rest_lo",
		"status": "placed", "order_number": "CHZ-LO1", "placed_at": time.Now().Format(time.RFC3339),
	})
	te.SeedOrder("order_lo2", map[string]interface{}{
		"customer_id": "c1", "restaurant_id": "other_rest",
		"status": "placed", "order_number": "CHZ-LO2", "placed_at": time.Now().Format(time.RFC3339),
	})

	rec := te.AuthRequest("GET", "/api/v1/orders", nil, "owner_lo", "restaurant_owner")
	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	resp := te.ParseResponse(rec)
	orders, _ := resp["data"].([]interface{})
	if len(orders) != 1 {
		t.Errorf("expected 1 order for this restaurant, got %d", len(orders))
	}
}

// ─── Restaurant Cancellation ───

func TestUpdateStatus_RestaurantCancels(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()
	seedOrderData(te)

	te.SeedOrder("order_rest_cancel", map[string]interface{}{
		"customer_id":   "cust_1",
		"restaurant_id": "rest_1",
		"status":        "confirmed",
		"order_number":  "CHZ-007",
	})

	rec := te.AuthRequest("PUT", "/api/v1/partner/orders/order_rest_cancel/status",
		map[string]interface{}{
			"status": "cancelled",
			"reason": "Out of ingredients",
		}, "owner_1", "restaurant_owner")

	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	doc := te.FakeAW.GetDocument("orders", "order_rest_cancel")
	if doc["cancelled_by"] != "restaurant_owner" {
		t.Errorf("expected cancelled_by=restaurant_owner, got %v", doc["cancelled_by"])
	}
	if doc["cancellation_reason"] != "Out of ingredients" {
		t.Errorf("expected cancellation_reason to match, got %v", doc["cancellation_reason"])
	}
}
