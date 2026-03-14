package handlers_test

import (
	"context"
	"testing"
	"time"

	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/internal/testutil"
	"github.com/chizze/backend/internal/websocket"
	"github.com/chizze/backend/internal/workers"
	"github.com/chizze/backend/pkg/appwrite"
)

// seedFlowData creates the base test data for flow tests.
func seedFlowData(te *testutil.TestEnv) {
	te.T.Helper()
	te.SeedUser("cust_1", map[string]interface{}{
		"phone": "+919876543210", "name": "Customer One", "role": "customer",
	})
	te.SeedUser("owner_1", map[string]interface{}{
		"phone": "+919876543211", "name": "Restaurant Owner", "role": "restaurant_owner",
	})
	te.SeedUser("dp_user_1", map[string]interface{}{
		"phone": "+919876543212", "name": "Rider A", "role": "delivery_partner",
	})
	te.SeedRestaurant("rest_1", "owner_1", 12.97, 77.59, true)
	te.SeedMenuItem("item_1", "rest_1", 250.0)
	te.SeedAddress("addr_1", "cust_1", 12.98, 77.60)
	te.SeedDeliveryPartner("dp_1", "dp_user_1", true, 12.97, 77.59)
	te.AddRiderToGeoSet("dp_user_1", 12.97, 77.59)
}

func createMatcher(te *testutil.TestEnv) *workers.DeliveryMatcher {
	te.T.Helper()
	awClient := appwrite.NewClient(te.Config)
	awService := services.NewAppwriteService(awClient)
	geoService := services.NewGeoService()
	hub := websocket.NewHub()
	go hub.Run()
	return workers.NewDeliveryMatcher(awService, geoService, te.RedisClient, hub, 15*time.Second)
}

// ─── End-to-End: Place → Delivered ───

func TestFlow_EndToEnd_PlaceToDelivered(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()
	seedFlowData(te)

	matcher := createMatcher(te)

	// 1. Customer places order
	rec := te.AuthRequest("POST", "/api/v1/orders", map[string]interface{}{
		"restaurant_id":      "rest_1",
		"delivery_address_id": "addr_1",
		"items": []map[string]interface{}{
			{"item_id": "item_1", "name": "Test Item", "quantity": 2, "price": 250.0},
		},
		"payment_method": "cod",
		"delivery_type":  "standard",
	}, "cust_1", "customer")

	if rec.Code != 201 {
		t.Fatalf("PlaceOrder: expected 201, got %d: %s", rec.Code, rec.Body.String())
	}
	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})
	orderID, _ := data["$id"].(string)

	// 2. Restaurant confirms
	rec = te.AuthRequest("PUT", "/api/v1/partner/orders/"+orderID+"/status",
		map[string]interface{}{"status": "confirmed"}, "owner_1", "restaurant_owner")
	if rec.Code != 200 {
		t.Fatalf("Confirm: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// 3. Restaurant prepares
	rec = te.AuthRequest("PUT", "/api/v1/partner/orders/"+orderID+"/status",
		map[string]interface{}{"status": "preparing"}, "owner_1", "restaurant_owner")
	if rec.Code != 200 {
		t.Fatalf("Preparing: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// 4. Restaurant marks ready
	rec = te.AuthRequest("PUT", "/api/v1/partner/orders/"+orderID+"/status",
		map[string]interface{}{"status": "ready"}, "owner_1", "restaurant_owner")
	if rec.Code != 200 {
		t.Fatalf("Ready: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// 5. Matcher assigns rider
	matcher.Process(context.Background())

	// Verify delivery request was created
	if te.FakeAW.DocumentCount("delivery_requests") == 0 {
		t.Fatal("expected delivery request to be created")
	}

	// 6. Rider accepts
	rec = te.AuthRequest("PUT", "/api/v1/delivery/orders/"+orderID+"/accept",
		nil, "dp_user_1", "delivery_partner")
	if rec.Code != 200 {
		t.Fatalf("Accept: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	doc := te.FakeAW.GetDocument("orders", orderID)
	if doc["delivery_partner_id"] != "dp_user_1" {
		t.Errorf("expected delivery_partner_id=dp_user_1, got %v", doc["delivery_partner_id"])
	}

	// 7. Rider picks up
	rec = te.AuthRequest("PUT", "/api/v1/delivery/orders/"+orderID+"/status",
		map[string]interface{}{"status": "pickedUp"}, "dp_user_1", "delivery_partner")
	if rec.Code != 200 {
		t.Fatalf("PickedUp: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// 8. Out for delivery
	rec = te.AuthRequest("PUT", "/api/v1/delivery/orders/"+orderID+"/status",
		map[string]interface{}{"status": "outForDelivery"}, "dp_user_1", "delivery_partner")
	if rec.Code != 200 {
		t.Fatalf("OutForDelivery: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// 9. Delivered
	rec = te.AuthRequest("PUT", "/api/v1/delivery/orders/"+orderID+"/status",
		map[string]interface{}{"status": "delivered"}, "dp_user_1", "delivery_partner")
	if rec.Code != 200 {
		t.Fatalf("Delivered: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// Final assertions
	finalDoc := te.FakeAW.GetDocument("orders", orderID)
	if finalDoc["status"] != "delivered" {
		t.Errorf("expected final status=delivered, got %v", finalDoc["status"])
	}
	if finalDoc["payment_status"] != "paid" {
		t.Errorf("expected COD payment_status=paid, got %v", finalDoc["payment_status"])
	}
	if finalDoc["delivered_at"] == nil || finalDoc["delivered_at"] == "" {
		t.Error("expected delivered_at to be set")
	}

	// Notifications should have been created
	if te.FakeAW.DocumentCount("notifications") == 0 {
		t.Error("expected notifications during flow")
	}
}

// ─── Customer Cancellation ───

func TestFlow_CustomerCancellation(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()
	seedFlowData(te)

	// Place order
	rec := te.AuthRequest("POST", "/api/v1/orders", map[string]interface{}{
		"restaurant_id":      "rest_1",
		"delivery_address_id": "addr_1",
		"items": []map[string]interface{}{
			{"item_id": "item_1", "name": "Test Item", "quantity": 1, "price": 250.0},
		},
		"payment_method": "cod",
	}, "cust_1", "customer")
	if rec.Code != 201 {
		t.Fatalf("PlaceOrder: expected 201, got %d: %s", rec.Code, rec.Body.String())
	}
	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})
	orderID, _ := data["$id"].(string)

	// Customer cancels
	rec = te.AuthRequest("PUT", "/api/v1/orders/"+orderID+"/cancel",
		map[string]interface{}{"reason": "Changed my mind"}, "cust_1", "customer")
	if rec.Code != 200 {
		t.Fatalf("Cancel: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	doc := te.FakeAW.GetDocument("orders", orderID)
	if doc["status"] != "cancelled" {
		t.Errorf("expected status=cancelled, got %v", doc["status"])
	}
	if doc["cancelled_by"] != "customer" {
		t.Errorf("expected cancelled_by=customer, got %v", doc["cancelled_by"])
	}

	// Try to confirm after cancellation - should fail
	rec = te.AuthRequest("PUT", "/api/v1/partner/orders/"+orderID+"/status",
		map[string]interface{}{"status": "confirmed"}, "owner_1", "restaurant_owner")
	if rec.Code != 400 {
		t.Fatalf("expected 400 for transition from cancelled, got %d", rec.Code)
	}
}

// ─── Restaurant Cancellation ───

func TestFlow_RestaurantCancellation(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()
	seedFlowData(te)

	// Place order
	rec := te.AuthRequest("POST", "/api/v1/orders", map[string]interface{}{
		"restaurant_id":      "rest_1",
		"delivery_address_id": "addr_1",
		"items": []map[string]interface{}{
			{"item_id": "item_1", "name": "Test Item", "quantity": 1, "price": 250.0},
		},
		"payment_method": "cod",
	}, "cust_1", "customer")
	if rec.Code != 201 {
		t.Fatalf("PlaceOrder: expected 201, got %d: %s", rec.Code, rec.Body.String())
	}
	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})
	orderID, _ := data["$id"].(string)

	// Restaurant confirms
	rec = te.AuthRequest("PUT", "/api/v1/partner/orders/"+orderID+"/status",
		map[string]interface{}{"status": "confirmed"}, "owner_1", "restaurant_owner")
	if rec.Code != 200 {
		t.Fatalf("Confirm: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// Restaurant cancels with reason
	rec = te.AuthRequest("PUT", "/api/v1/partner/orders/"+orderID+"/status",
		map[string]interface{}{
			"status": "cancelled",
			"reason": "Out of ingredients",
		}, "owner_1", "restaurant_owner")
	if rec.Code != 200 {
		t.Fatalf("Cancel: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	doc := te.FakeAW.GetDocument("orders", orderID)
	if doc["cancelled_by"] != "restaurant_owner" {
		t.Errorf("expected cancelled_by=restaurant_owner, got %v", doc["cancelled_by"])
	}
	if doc["cancellation_reason"] != "Out of ingredients" {
		t.Errorf("expected cancellation_reason, got %v", doc["cancellation_reason"])
	}
}

// ─── Rejection Cascade ───

func TestFlow_RejectionCascade(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	// Seed users and riders
	te.SeedUser("cust_1", map[string]interface{}{"phone": "+919876543210", "name": "Customer", "role": "customer"})
	te.SeedUser("owner_1", map[string]interface{}{"phone": "+919876543211", "name": "Owner", "role": "restaurant_owner"})
	te.SeedUser("rider_A", map[string]interface{}{"phone": "+919876543212", "name": "Rider A", "role": "delivery_partner"})
	te.SeedUser("rider_B", map[string]interface{}{"phone": "+919876543213", "name": "Rider B", "role": "delivery_partner"})
	te.SeedUser("rider_C", map[string]interface{}{"phone": "+919876543214", "name": "Rider C", "role": "delivery_partner"})

	te.SeedRestaurant("rest_1", "owner_1", 12.97, 77.59, true)
	te.SeedMenuItem("item_1", "rest_1", 200.0)
	te.SeedAddress("addr_1", "cust_1", 12.98, 77.60)

	te.SeedDeliveryPartner("dp_A", "rider_A", true, 12.970, 77.590)
	te.SeedDeliveryPartner("dp_B", "rider_B", true, 12.971, 77.591)
	te.SeedDeliveryPartner("dp_C", "rider_C", true, 12.972, 77.592)

	te.AddRiderToGeoSet("rider_A", 12.970, 77.590)
	te.AddRiderToGeoSet("rider_B", 12.971, 77.591)
	te.AddRiderToGeoSet("rider_C", 12.972, 77.592)

	matcher := createMatcher(te)

	// Place and progress order to ready
	rec := te.AuthRequest("POST", "/api/v1/orders", map[string]interface{}{
		"restaurant_id":      "rest_1",
		"delivery_address_id": "addr_1",
		"items": []map[string]interface{}{
			{"item_id": "item_1", "name": "Test", "quantity": 1, "price": 200.0},
		},
		"payment_method": "cod",
	}, "cust_1", "customer")
	if rec.Code != 201 {
		t.Fatalf("PlaceOrder: expected 201, got %d: %s", rec.Code, rec.Body.String())
	}
	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})
	orderID, _ := data["$id"].(string)

	for _, status := range []string{"confirmed", "preparing", "ready"} {
		rec = te.AuthRequest("PUT", "/api/v1/partner/orders/"+orderID+"/status",
			map[string]interface{}{"status": status}, "owner_1", "restaurant_owner")
		if rec.Code != 200 {
			t.Fatalf("UpdateStatus(%s): expected 200, got %d", status, rec.Code)
		}
	}

	ctx := context.Background()

	// Round 1: matcher assigns closest rider (rider_A)
	matcher.Process(ctx)
	reqDocs := te.FakeAW.AllDocuments("delivery_requests")
	if len(reqDocs) == 0 {
		t.Fatal("expected delivery request after round 1")
	}
	firstRider, _ := reqDocs[0]["rider_id"].(string)
	t.Logf("Round 1: assigned to %s", firstRider)

	// Rider A rejects
	rec = te.AuthRequest("PUT", "/api/v1/delivery/orders/"+orderID+"/reject",
		nil, firstRider, "delivery_partner")
	if rec.Code != 200 {
		t.Fatalf("Reject round 1: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// Verify rider_A is in rejected set
	members, _ := te.RedisClient.SMembers(ctx, "rejected_riders:"+orderID)
	if len(members) == 0 || members[0] != firstRider {
		t.Errorf("expected %s in rejected set, got %v", firstRider, members)
	}

	// Round 2: matcher should skip the rejected rider and assign another
	matcher.Process(ctx)
	reqDocs = te.FakeAW.AllDocuments("delivery_requests")
	if len(reqDocs) < 2 {
		t.Fatal("expected second delivery request after round 2")
	}

	// Find the second request (different rider)
	secondRider := ""
	for _, d := range reqDocs {
		rid, _ := d["rider_id"].(string)
		if rid != firstRider {
			secondRider = rid
			break
		}
	}
	if secondRider == "" {
		t.Fatal("expected a different rider in round 2")
	}
	t.Logf("Round 2: assigned to %s", secondRider)

	// Second rider accepts
	rec = te.AuthRequest("PUT", "/api/v1/delivery/orders/"+orderID+"/accept",
		nil, secondRider, "delivery_partner")
	if rec.Code != 200 {
		t.Fatalf("Accept: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// Verify order is assigned to second rider
	finalDoc := te.FakeAW.GetDocument("orders", orderID)
	if finalDoc["delivery_partner_id"] != secondRider {
		t.Errorf("expected delivery_partner_id=%s, got %v", secondRider, finalDoc["delivery_partner_id"])
	}
}
