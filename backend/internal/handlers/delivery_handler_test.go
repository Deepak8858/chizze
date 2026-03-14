package handlers_test

import (
	"context"
	"testing"
	"time"

	"github.com/chizze/backend/internal/testutil"
)

// ─── AcceptOrder ───

func TestAcceptOrder_Success(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("cust_1", map[string]interface{}{"phone": "+919876543210", "name": "Customer", "role": "customer"})
	te.SeedUser("dp_user_1", map[string]interface{}{"phone": "+919876543212", "name": "Rider One", "role": "delivery_partner"})
	te.SeedDeliveryPartner("dp_1", "dp_user_1", true, 12.97, 77.59)
	te.SeedRestaurant("rest_1", "owner_1", 12.97, 77.59, true)
	te.SeedOrder("order_ready", map[string]interface{}{
		"customer_id":   "cust_1",
		"restaurant_id": "rest_1",
		"status":        "ready",
		"order_number":  "CHZ-100",
	})

	rec := te.AuthRequest("PUT", "/api/v1/delivery/orders/order_ready/accept", nil, "dp_user_1", "delivery_partner")

	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// Order should have delivery partner assigned
	doc := te.FakeAW.GetDocument("orders", "order_ready")
	if doc["delivery_partner_id"] != "dp_user_1" {
		t.Errorf("expected delivery_partner_id=dp_user_1, got %v", doc["delivery_partner_id"])
	}

	// Notification should be created for customer
	if te.FakeAW.DocumentCount("notifications") == 0 {
		t.Error("expected notification to be created for customer")
	}
}

func TestAcceptOrder_AlreadyAssigned(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("dp_user_1", map[string]interface{}{"phone": "+919876543212", "name": "Rider", "role": "delivery_partner"})
	te.SeedDeliveryPartner("dp_1", "dp_user_1", true, 12.97, 77.59)
	te.SeedOrder("order_assigned", map[string]interface{}{
		"customer_id":         "cust_1",
		"restaurant_id":       "rest_1",
		"status":              "ready",
		"delivery_partner_id": "other_rider",
		"order_number":        "CHZ-101",
	})

	rec := te.AuthRequest("PUT", "/api/v1/delivery/orders/order_assigned/accept", nil, "dp_user_1", "delivery_partner")

	if rec.Code != 400 {
		t.Fatalf("expected 400 for already assigned, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestAcceptOrder_NotReady(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("dp_user_1", map[string]interface{}{"phone": "+919876543212", "name": "Rider", "role": "delivery_partner"})
	te.SeedDeliveryPartner("dp_1", "dp_user_1", true, 12.97, 77.59)
	te.SeedOrder("order_prep", map[string]interface{}{
		"customer_id":   "cust_1",
		"restaurant_id": "rest_1",
		"status":        "preparing",
		"order_number":  "CHZ-102",
	})

	rec := te.AuthRequest("PUT", "/api/v1/delivery/orders/order_prep/accept", nil, "dp_user_1", "delivery_partner")

	if rec.Code != 400 {
		t.Fatalf("expected 400 for not-ready order, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestAcceptOrder_PartnerOffline(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("dp_user_1", map[string]interface{}{"phone": "+919876543212", "name": "Rider", "role": "delivery_partner"})
	te.SeedDeliveryPartner("dp_1", "dp_user_1", false, 12.97, 77.59) // offline
	te.SeedOrder("order_ready2", map[string]interface{}{
		"customer_id":   "cust_1",
		"restaurant_id": "rest_1",
		"status":        "ready",
		"order_number":  "CHZ-103",
	})

	rec := te.AuthRequest("PUT", "/api/v1/delivery/orders/order_ready2/accept", nil, "dp_user_1", "delivery_partner")

	if rec.Code != 400 {
		t.Fatalf("expected 400 for offline partner, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestAcceptOrder_DistributedLock(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("dp_user_1", map[string]interface{}{"phone": "+919876543212", "name": "Rider", "role": "delivery_partner"})
	te.SeedDeliveryPartner("dp_1", "dp_user_1", true, 12.97, 77.59)
	te.SeedOrder("order_locked", map[string]interface{}{
		"customer_id":   "cust_1",
		"restaurant_id": "rest_1",
		"status":        "ready",
		"order_number":  "CHZ-104",
	})

	// Pre-set the lock to simulate another rider accepting
	te.MiniRedis.Set("delivery_lock:order_locked", "other_rider")
	te.MiniRedis.SetTTL("delivery_lock:order_locked", 30*time.Second)

	rec := te.AuthRequest("PUT", "/api/v1/delivery/orders/order_locked/accept", nil, "dp_user_1", "delivery_partner")

	if rec.Code != 400 {
		t.Fatalf("expected 400 for locked order, got %d: %s", rec.Code, rec.Body.String())
	}
}

// ─── RejectOrder ───

func TestRejectOrder_Success(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("dp_user_1", map[string]interface{}{"phone": "+919876543212", "name": "Rider", "role": "delivery_partner"})
	te.SeedDeliveryPartner("dp_1", "dp_user_1", true, 12.97, 77.59)
	te.SeedOrder("order_reject", map[string]interface{}{
		"customer_id":   "cust_1",
		"restaurant_id": "rest_1",
		"status":        "ready",
		"order_number":  "CHZ-105",
	})

	// Set pending_delivery key
	te.MiniRedis.Set("pending_delivery:order_reject", "dp_user_1")

	rec := te.AuthRequest("PUT", "/api/v1/delivery/orders/order_reject/reject", nil, "dp_user_1", "delivery_partner")

	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// pending_delivery key should be cleared
	if te.MiniRedis.Exists("pending_delivery:order_reject") {
		t.Error("expected pending_delivery key to be cleared")
	}

	// Rider should be in rejected set
	ctx := context.Background()
	members, _ := te.RedisClient.SMembers(ctx, "rejected_riders:order_reject")
	found := false
	for _, m := range members {
		if m == "dp_user_1" {
			found = true
			break
		}
	}
	if !found {
		t.Error("expected dp_user_1 in rejected_riders set")
	}

	// matcherCallback should have been triggered
	if !te.MatcherCalled {
		t.Error("expected matcherCallback to fire after rejection")
	}
}

func TestRejectOrder_UnassignsIfAssigned(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("dp_user_1", map[string]interface{}{"phone": "+919876543212", "name": "Rider", "role": "delivery_partner"})
	te.SeedDeliveryPartner("dp_1", "dp_user_1", true, 12.97, 77.59)
	te.SeedOrder("order_unassign", map[string]interface{}{
		"customer_id":         "cust_1",
		"restaurant_id":       "rest_1",
		"status":              "ready",
		"delivery_partner_id": "dp_user_1", // assigned to this rider
		"order_number":        "CHZ-106",
	})

	rec := te.AuthRequest("PUT", "/api/v1/delivery/orders/order_unassign/reject", nil, "dp_user_1", "delivery_partner")

	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	doc := te.FakeAW.GetDocument("orders", "order_unassign")
	if doc["delivery_partner_id"] != "" {
		t.Errorf("expected delivery_partner_id to be cleared, got %v", doc["delivery_partner_id"])
	}
}

// ─── ToggleOnline ───

func TestToggleOnline_GoOnline(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("dp_user_1", map[string]interface{}{"phone": "+919876543212", "name": "Rider", "role": "delivery_partner"})
	te.SeedDeliveryPartner("dp_1", "dp_user_1", false, 12.97, 77.59)

	rec := te.AuthRequest("PUT", "/api/v1/delivery/status",
		map[string]interface{}{"is_online": true}, "dp_user_1", "delivery_partner")

	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	doc := te.FakeAW.GetDocument("delivery_partners", "dp_1")
	if doc["is_online"] != true {
		t.Errorf("expected is_online=true, got %v", doc["is_online"])
	}
	if doc["login_at"] == nil || doc["login_at"] == "" {
		t.Error("expected login_at to be set when going online")
	}
}

func TestToggleOnline_GoOffline(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("dp_user_1", map[string]interface{}{"phone": "+919876543212", "name": "Rider", "role": "delivery_partner"})
	te.SeedDeliveryPartner("dp_1", "dp_user_1", true, 12.97, 77.59)
	te.AddRiderToGeoSet("dp_user_1", 12.97, 77.59)

	rec := te.AuthRequest("PUT", "/api/v1/delivery/status",
		map[string]interface{}{"is_online": false}, "dp_user_1", "delivery_partner")

	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	doc := te.FakeAW.GetDocument("delivery_partners", "dp_1")
	if doc["is_online"] != false {
		t.Errorf("expected is_online=false, got %v", doc["is_online"])
	}
}

// ─── UpdateLocation ───

func TestUpdateLocation_Success(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("dp_user_1", map[string]interface{}{"phone": "+919876543212", "name": "Rider", "role": "delivery_partner"})
	te.SeedDeliveryPartner("dp_1", "dp_user_1", true, 12.97, 77.59)

	rec := te.AuthRequest("PUT", "/api/v1/delivery/location",
		map[string]interface{}{
			"latitude":  12.98,
			"longitude": 77.60,
			"heading":   45.0,
			"speed":     25.0,
		}, "dp_user_1", "delivery_partner")

	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	doc := te.FakeAW.GetDocument("delivery_partners", "dp_1")
	if doc["current_latitude"] != 12.98 {
		t.Errorf("expected current_latitude=12.98, got %v", doc["current_latitude"])
	}
	if doc["current_longitude"] != 77.60 {
		t.Errorf("expected current_longitude=77.60, got %v", doc["current_longitude"])
	}
}

// ─── Dashboard ───

func TestDashboard_Success(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("dp_user_1", map[string]interface{}{"phone": "+919876543212", "name": "Rider", "role": "delivery_partner"})
	te.SeedDeliveryPartner("dp_1", "dp_user_1", true, 12.97, 77.59)

	rec := te.AuthRequest("GET", "/api/v1/delivery/dashboard", nil, "dp_user_1", "delivery_partner")

	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})
	if data == nil {
		t.Fatal("expected data in response")
	}
}

// ─── ActiveOrders ───

func TestActiveOrders_AssignedMode(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("dp_user_1", map[string]interface{}{"phone": "+919876543212", "name": "Rider", "role": "delivery_partner"})
	te.SeedDeliveryPartner("dp_1", "dp_user_1", true, 12.97, 77.59)
	te.SeedOrder("order_assigned_1", map[string]interface{}{
		"customer_id":         "cust_1",
		"restaurant_id":       "rest_1",
		"delivery_partner_id": "dp_user_1",
		"status":              "pickedUp",
		"order_number":        "CHZ-AO1",
		"placed_at":           time.Now().Format(time.RFC3339),
	})
	te.SeedOrder("order_other", map[string]interface{}{
		"customer_id":         "cust_1",
		"restaurant_id":       "rest_1",
		"delivery_partner_id": "other_dp",
		"status":              "pickedUp",
		"order_number":        "CHZ-AO2",
		"placed_at":           time.Now().Format(time.RFC3339),
	})

	rec := te.AuthRequest("GET", "/api/v1/delivery/orders?mode=assigned", nil, "dp_user_1", "delivery_partner")
	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	resp := te.ParseResponse(rec)
	items, _ := resp["data"].([]interface{})
	if len(items) != 1 {
		t.Errorf("expected 1 assigned order, got %d", len(items))
	}
}

func TestActiveOrders_AvailableMode(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("dp_user_1", map[string]interface{}{"phone": "+919876543212", "name": "Rider", "role": "delivery_partner"})
	te.SeedDeliveryPartner("dp_1", "dp_user_1", true, 12.97, 77.59)
	te.SeedUser("cust_1", map[string]interface{}{"phone": "+919876543210", "name": "C", "role": "customer"})

	// Available order (no partner assigned)
	te.SeedOrder("order_avail", map[string]interface{}{
		"customer_id":   "cust_1",
		"restaurant_id": "rest_1",
		"status":        "ready",
		"order_number":  "CHZ-AV1",
		"placed_at":     time.Now().Format(time.RFC3339),
	})
	// Already assigned order (not available)
	te.SeedOrder("order_taken", map[string]interface{}{
		"customer_id":         "cust_1",
		"restaurant_id":       "rest_1",
		"delivery_partner_id": "other_dp",
		"status":              "ready",
		"order_number":        "CHZ-AV2",
		"placed_at":           time.Now().Format(time.RFC3339),
	})

	rec := te.AuthRequest("GET", "/api/v1/delivery/orders?mode=available", nil, "dp_user_1", "delivery_partner")
	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	resp := te.ParseResponse(rec)
	items, _ := resp["data"].([]interface{})
	if len(items) < 1 {
		t.Errorf("expected at least 1 available order, got %d", len(items))
	}
}

// ─── Earnings ───

func TestEarnings_Success(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("dp_earn", map[string]interface{}{"phone": "+919876543212", "name": "Rider", "role": "delivery_partner"})
	te.SeedDeliveryPartner("dp_e1", "dp_earn", true, 12.97, 77.59)
	te.SeedRestaurant("rest_e", "owner_e", 12.97, 77.59, true)

	// Seed delivered orders
	te.SeedOrder("order_e1", map[string]interface{}{
		"customer_id":         "c1",
		"restaurant_id":       "rest_e",
		"delivery_partner_id": "dp_earn",
		"status":              "delivered",
		"delivery_fee":        30.0,
		"tip":                 10.0,
		"order_number":        "CHZ-E1",
		"placed_at":           time.Now().Format(time.RFC3339),
		"delivered_at":        time.Now().Format(time.RFC3339),
	})
	te.SeedOrder("order_e2", map[string]interface{}{
		"customer_id":         "c1",
		"restaurant_id":       "rest_e",
		"delivery_partner_id": "dp_earn",
		"status":              "delivered",
		"delivery_fee":        40.0,
		"tip":                 5.0,
		"order_number":        "CHZ-E2",
		"placed_at":           time.Now().Format(time.RFC3339),
		"delivered_at":        time.Now().Format(time.RFC3339),
	})

	rec := te.AuthRequest("GET", "/api/v1/delivery/earnings?period=week", nil, "dp_earn", "delivery_partner")
	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})

	weeklyTotal, _ := data["weekly_total"].(float64)
	if weeklyTotal != 85.0 { // (30+10) + (40+5)
		t.Errorf("expected weekly_total=85, got %v", weeklyTotal)
	}
	totalTrips, _ := data["total_trips"].(float64)
	if totalTrips != 2 {
		t.Errorf("expected total_trips=2, got %v", totalTrips)
	}
}

func TestEarnings_DayPeriod(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("dp_ed", map[string]interface{}{"phone": "+919876543212", "role": "delivery_partner"})
	te.SeedDeliveryPartner("dp_ed1", "dp_ed", true, 12.97, 77.59)

	rec := te.AuthRequest("GET", "/api/v1/delivery/earnings?period=day", nil, "dp_ed", "delivery_partner")
	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})
	if data["period"] != "day" {
		t.Errorf("expected period=day, got %v", data["period"])
	}
}

// ─── Performance ───

func TestPerformance_Success(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("dp_perf", map[string]interface{}{"phone": "+919876543212", "name": "Rider", "role": "delivery_partner"})
	te.SeedDeliveryPartner("dp_p1", "dp_perf", true, 12.97, 77.59)

	// Seed 3 delivered + 1 cancelled
	for i := 0; i < 3; i++ {
		te.SeedOrder("order_p"+string(rune('A'+i)), map[string]interface{}{
			"customer_id":         "c1",
			"restaurant_id":       "r1",
			"delivery_partner_id": "dp_perf",
			"status":              "delivered",
			"order_number":        "CHZ-P" + string(rune('A'+i)),
			"placed_at":           time.Now().Format(time.RFC3339),
		})
	}
	te.SeedOrder("order_pX", map[string]interface{}{
		"customer_id":         "c1",
		"restaurant_id":       "r1",
		"delivery_partner_id": "dp_perf",
		"status":              "cancelled",
		"order_number":        "CHZ-PX",
		"placed_at":           time.Now().Format(time.RFC3339),
	})

	rec := te.AuthRequest("GET", "/api/v1/delivery/performance", nil, "dp_perf", "delivery_partner")
	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})

	totalOrders, _ := data["total_orders"].(float64)
	if totalOrders != 4 {
		t.Errorf("expected total_orders=4, got %v", totalOrders)
	}
	deliveredOrders, _ := data["delivered_orders"].(float64)
	if deliveredOrders != 3 {
		t.Errorf("expected delivered_orders=3, got %v", deliveredOrders)
	}
	completionRate, _ := data["completion_rate"].(float64)
	if completionRate != 75.0 {
		t.Errorf("expected completion_rate=75, got %v", completionRate)
	}
}

// ─── Profile ───

func TestGetProfile_Success(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("dp_prof", map[string]interface{}{"phone": "+919876543212", "name": "Rider Pro", "role": "delivery_partner"})
	te.SeedDeliveryPartner("dp_pr1", "dp_prof", true, 12.97, 77.59)

	rec := te.AuthRequest("GET", "/api/v1/delivery/profile", nil, "dp_prof", "delivery_partner")
	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})
	if data["user_id"] != "dp_prof" {
		t.Errorf("expected user_id=dp_prof, got %v", data["user_id"])
	}
}

func TestGetProfile_NotFound(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("dp_nopartner", map[string]interface{}{"phone": "+919876543212", "role": "delivery_partner"})
	// No delivery partner doc seeded

	rec := te.AuthRequest("GET", "/api/v1/delivery/profile", nil, "dp_nopartner", "delivery_partner")
	if rec.Code != 404 {
		t.Fatalf("expected 404, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestUpdateProfile_Success(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("dp_up", map[string]interface{}{"phone": "+919876543212", "name": "Rider", "role": "delivery_partner"})
	te.SeedDeliveryPartner("dp_up1", "dp_up", true, 12.97, 77.59)

	rec := te.AuthRequest("PUT", "/api/v1/delivery/profile", map[string]interface{}{
		"vehicle_type":   "scooter",
		"vehicle_number": "KA01AB9999",
		"upi_id":         "rider@upi",
	}, "dp_up", "delivery_partner")

	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	doc := te.FakeAW.GetDocument("delivery_partners", "dp_up1")
	if doc["vehicle_type"] != "scooter" {
		t.Errorf("expected vehicle_type=scooter, got %v", doc["vehicle_type"])
	}
	if doc["upi_id"] != "rider@upi" {
		t.Errorf("expected upi_id=rider@upi, got %v", doc["upi_id"])
	}
}

func TestUpdateProfile_NoFieldsToUpdate(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("dp_nf", map[string]interface{}{"phone": "+919876543212", "role": "delivery_partner"})
	te.SeedDeliveryPartner("dp_nf1", "dp_nf", true, 12.97, 77.59)

	rec := te.AuthRequest("PUT", "/api/v1/delivery/profile", map[string]interface{}{}, "dp_nf", "delivery_partner")
	if rec.Code != 400 {
		t.Fatalf("expected 400 for empty update, got %d: %s", rec.Code, rec.Body.String())
	}
}

// ─── Payouts ───

func TestListPayouts_Success(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("dp_pay", map[string]interface{}{"phone": "+919876543212", "role": "delivery_partner"})
	te.SeedDeliveryPartner("dp_pay1", "dp_pay", true, 12.97, 77.59)
	te.SeedPayout("payout_1", map[string]interface{}{
		"user_id":    "dp_pay",
		"partner_id": "dp_pay1",
		"amount":     500.0,
		"status":     "completed",
		"method":     "bank_transfer",
		"created_at": time.Now().Format(time.RFC3339),
	})

	rec := te.AuthRequest("GET", "/api/v1/delivery/payouts", nil, "dp_pay", "delivery_partner")
	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	resp := te.ParseResponse(rec)
	items, _ := resp["data"].([]interface{})
	if len(items) != 1 {
		t.Errorf("expected 1 payout, got %d", len(items))
	}
}

func TestRequestPayout_Success(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("dp_rp", map[string]interface{}{"phone": "+919876543212", "name": "Rider", "role": "delivery_partner"})
	te.FakeAW.SeedDocument("delivery_partners", "dp_rp1", map[string]interface{}{
		"user_id":          "dp_rp",
		"is_online":        true,
		"total_earnings":   1000.0,
		"total_deliveries": 50,
		"vehicle_type":     "bike",
		"rating":           4.5,
	})

	rec := te.AuthRequest("POST", "/api/v1/delivery/payouts/request", map[string]interface{}{
		"amount": 500.0,
		"method": "bank_transfer",
	}, "dp_rp", "delivery_partner")

	if rec.Code != 201 {
		t.Fatalf("expected 201, got %d: %s", rec.Code, rec.Body.String())
	}

	// Verify balance deducted
	doc := te.FakeAW.GetDocument("delivery_partners", "dp_rp1")
	newBalance, _ := doc["total_earnings"].(float64)
	if newBalance != 500.0 {
		t.Errorf("expected remaining balance=500, got %v", newBalance)
	}
}

func TestRequestPayout_MinimumAmount(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("dp_min", map[string]interface{}{"phone": "+919876543212", "role": "delivery_partner"})
	te.FakeAW.SeedDocument("delivery_partners", "dp_min1", map[string]interface{}{
		"user_id": "dp_min", "is_online": true, "total_earnings": 1000.0,
		"vehicle_type": "bike", "rating": 4.5,
	})

	rec := te.AuthRequest("POST", "/api/v1/delivery/payouts/request", map[string]interface{}{
		"amount": 50.0,
		"method": "upi",
	}, "dp_min", "delivery_partner")
	if rec.Code != 400 {
		t.Fatalf("expected 400 for below minimum, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestRequestPayout_InsufficientBalance(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("dp_insuf", map[string]interface{}{"phone": "+919876543212", "role": "delivery_partner"})
	te.FakeAW.SeedDocument("delivery_partners", "dp_insuf1", map[string]interface{}{
		"user_id": "dp_insuf", "is_online": true, "total_earnings": 100.0,
		"vehicle_type": "bike", "rating": 4.5,
	})

	rec := te.AuthRequest("POST", "/api/v1/delivery/payouts/request", map[string]interface{}{
		"amount": 500.0,
		"method": "bank_transfer",
	}, "dp_insuf", "delivery_partner")
	if rec.Code != 400 {
		t.Fatalf("expected 400 for insufficient balance, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestRequestPayout_DuplicatePending(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("dp_dup", map[string]interface{}{"phone": "+919876543212", "role": "delivery_partner"})
	te.FakeAW.SeedDocument("delivery_partners", "dp_dup1", map[string]interface{}{
		"user_id": "dp_dup", "is_online": true, "total_earnings": 2000.0,
		"vehicle_type": "bike", "rating": 4.5,
	})
	// Existing pending payout
	te.SeedPayout("payout_dup", map[string]interface{}{
		"user_id": "dp_dup", "status": "pending", "amount": 500.0, "method": "upi",
	})

	rec := te.AuthRequest("POST", "/api/v1/delivery/payouts/request", map[string]interface{}{
		"amount": 500.0,
		"method": "bank_transfer",
	}, "dp_dup", "delivery_partner")
	if rec.Code != 400 {
		t.Fatalf("expected 400 for duplicate pending, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestRequestPayout_InvalidMethod(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("dp_im", map[string]interface{}{"phone": "+919876543212", "role": "delivery_partner"})
	te.FakeAW.SeedDocument("delivery_partners", "dp_im1", map[string]interface{}{
		"user_id": "dp_im", "is_online": true, "total_earnings": 1000.0,
		"vehicle_type": "bike", "rating": 4.5,
	})

	rec := te.AuthRequest("POST", "/api/v1/delivery/payouts/request", map[string]interface{}{
		"amount": 500.0,
		"method": "crypto",
	}, "dp_im", "delivery_partner")
	if rec.Code != 400 {
		t.Fatalf("expected 400 for invalid method, got %d: %s", rec.Code, rec.Body.String())
	}
}

// ─── ReportIssue ───

func TestReportIssue_Success(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("dp_ri", map[string]interface{}{"phone": "+919876543212", "name": "Rider", "role": "delivery_partner"})
	te.SeedUser("cust_ri", map[string]interface{}{"phone": "+919876543210", "name": "Customer", "role": "customer"})
	te.SeedUser("owner_ri", map[string]interface{}{"phone": "+919876543211", "name": "Owner", "role": "restaurant_owner"})
	te.SeedRestaurant("rest_ri", "owner_ri", 12.97, 77.59, true)
	te.SeedDeliveryPartner("dp_ri1", "dp_ri", true, 12.97, 77.59)
	te.SeedOrder("order_ri", map[string]interface{}{
		"customer_id":         "cust_ri",
		"restaurant_id":       "rest_ri",
		"delivery_partner_id": "dp_ri",
		"status":              "pickedUp",
		"order_number":        "CHZ-RI1",
	})

	rec := te.AuthRequest("POST", "/api/v1/delivery/orders/order_ri/report", map[string]interface{}{
		"reason":  "Customer unreachable",
		"details": "Called 3 times, no answer",
	}, "dp_ri", "delivery_partner")

	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// Verify issue was created
	if te.FakeAW.DocumentCount("delivery_issues") == 0 {
		t.Error("expected delivery_issues document to be created")
	}
}

func TestReportIssue_NotAssigned(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("dp_ri2", map[string]interface{}{"phone": "+919876543212", "role": "delivery_partner"})
	te.SeedDeliveryPartner("dp_ri2p", "dp_ri2", true, 12.97, 77.59)
	te.SeedOrder("order_ri2", map[string]interface{}{
		"customer_id":         "c1",
		"restaurant_id":       "r1",
		"delivery_partner_id": "other_dp",
		"status":              "pickedUp",
		"order_number":        "CHZ-RI2",
	})

	rec := te.AuthRequest("POST", "/api/v1/delivery/orders/order_ri2/report", map[string]interface{}{
		"reason": "Test",
	}, "dp_ri2", "delivery_partner")

	if rec.Code != 403 {
		t.Fatalf("expected 403, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestReportIssue_InvalidStatus(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("dp_ri3", map[string]interface{}{"phone": "+919876543212", "role": "delivery_partner"})
	te.SeedDeliveryPartner("dp_ri3p", "dp_ri3", true, 12.97, 77.59)
	te.SeedOrder("order_ri3", map[string]interface{}{
		"customer_id":         "c1",
		"restaurant_id":       "r1",
		"delivery_partner_id": "dp_ri3",
		"status":              "delivered", // not an active status
		"order_number":        "CHZ-RI3",
	})

	rec := te.AuthRequest("POST", "/api/v1/delivery/orders/order_ri3/report", map[string]interface{}{
		"reason": "Late",
	}, "dp_ri3", "delivery_partner")

	if rec.Code != 400 {
		t.Fatalf("expected 400 for invalid status, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestReportIssue_MissingReason(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("dp_ri4", map[string]interface{}{"phone": "+919876543212", "role": "delivery_partner"})
	te.SeedDeliveryPartner("dp_ri4p", "dp_ri4", true, 12.97, 77.59)
	te.SeedOrder("order_ri4", map[string]interface{}{
		"customer_id":         "c1",
		"restaurant_id":       "r1",
		"delivery_partner_id": "dp_ri4",
		"status":              "pickedUp",
		"order_number":        "CHZ-RI4",
	})

	rec := te.AuthRequest("POST", "/api/v1/delivery/orders/order_ri4/report", map[string]interface{}{}, "dp_ri4", "delivery_partner")
	if rec.Code != 400 {
		t.Fatalf("expected 400 for missing reason, got %d", rec.Code)
	}
}

func TestReportIssue_EmptyReasonTrimmed(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("dp_ri5", map[string]interface{}{"phone": "+919876543212", "role": "delivery_partner"})
	te.SeedDeliveryPartner("dp_ri5p", "dp_ri5", true, 12.97, 77.59)
	te.SeedOrder("order_ri5", map[string]interface{}{
		"customer_id":         "c1",
		"restaurant_id":       "r1",
		"delivery_partner_id": "dp_ri5",
		"status":              "pickedUp",
		"order_number":        "CHZ-RI5",
	})

	rec := te.AuthRequest("POST", "/api/v1/delivery/orders/order_ri5/report", map[string]interface{}{
		"reason": "   ",
	}, "dp_ri5", "delivery_partner")
	if rec.Code != 400 {
		t.Fatalf("expected 400 for whitespace-only reason, got %d", rec.Code)
	}
}

// ─── UpdateLocation with broadcast ───

func TestUpdateLocation_BroadcastToActiveOrders(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("dp_loc_b", map[string]interface{}{"phone": "+919876543212", "name": "Rider", "role": "delivery_partner"})
	te.SeedDeliveryPartner("dp_loc_b1", "dp_loc_b", true, 12.97, 77.59)

	// Active order assigned to this rider
	te.SeedOrder("order_loc_active", map[string]interface{}{
		"customer_id":         "cust_loc",
		"restaurant_id":       "rest_loc",
		"delivery_partner_id": "dp_loc_b",
		"status":              "outForDelivery",
		"order_number":        "CHZ-LOC1",
	})

	rec := te.AuthRequest("PUT", "/api/v1/delivery/location", map[string]interface{}{
		"latitude":  12.99,
		"longitude": 77.61,
		"heading":   90.0,
		"speed":     30.0,
	}, "dp_loc_b", "delivery_partner")

	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
}

// ─── AcceptOrder clears Redis keys ───

func TestAcceptOrder_ClearsRedisKeys(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("cust_ck", map[string]interface{}{"phone": "+919876543210", "name": "Customer", "role": "customer"})
	te.SeedUser("dp_ck", map[string]interface{}{"phone": "+919876543212", "name": "Rider", "role": "delivery_partner"})
	te.SeedDeliveryPartner("dp_ck1", "dp_ck", true, 12.97, 77.59)
	te.SeedRestaurant("rest_ck", "owner_ck", 12.97, 77.59, true)
	te.SeedOrder("order_ck", map[string]interface{}{
		"customer_id":   "cust_ck",
		"restaurant_id": "rest_ck",
		"status":        "ready",
		"order_number":  "CHZ-CK1",
	})

	// Set keys that should be cleared on accept
	te.MiniRedis.Set("pending_delivery:order_ck", "dp_ck")
	ctx := context.Background()
	te.RedisClient.SAdd(ctx, "rejected_riders:order_ck", "some_rider")

	rec := te.AuthRequest("PUT", "/api/v1/delivery/orders/order_ck/accept", nil, "dp_ck", "delivery_partner")
	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// pending_delivery should be cleared
	if te.MiniRedis.Exists("pending_delivery:order_ck") {
		t.Error("expected pending_delivery key to be cleared after accept")
	}
	// rejected_riders should be cleared
	if te.MiniRedis.Exists("rejected_riders:order_ck") {
		t.Error("expected rejected_riders key to be cleared after accept")
	}
}
