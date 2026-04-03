package handlers_test

import (
	"fmt"
	"testing"
	"time"

	"github.com/chizze/backend/internal/handlers"
	"github.com/chizze/backend/internal/middleware"
	"github.com/chizze/backend/internal/testutil"
)

func registerAdminOrderRoutes(te *testutil.TestEnv) {
	te.T.Helper()

	adminHandler := handlers.NewAdminHandler(te.AWService, te.RedisClient, te.Hub)
	v1 := te.Router.Group("/api/v1")
	admin := v1.Group("/admin")
	admin.Use(middleware.Auth(te.Config, te.RedisClient))
	admin.Use(middleware.RequireRole("admin", "super_admin"))
	admin.GET("/orders/stuck/preview", adminHandler.PreviewStuckOrders)
	admin.POST("/orders/stuck/delete", adminHandler.DeleteStuckOrders)
	admin.GET("/orders/:id", adminHandler.GetOrder)
}

func asInt(t *testing.T, value interface{}) int {
	t.Helper()
	n, ok := value.(float64)
	if !ok {
		t.Fatalf("expected numeric value, got %#v", value)
	}
	return int(n)
}

func asStringSlice(t *testing.T, value interface{}) []string {
	t.Helper()
	items, ok := value.([]interface{})
	if !ok {
		t.Fatalf("expected []interface{}, got %#v", value)
	}
	out := make([]string, 0, len(items))
	for _, item := range items {
		s, ok := item.(string)
		if !ok {
			t.Fatalf("expected string item, got %#v", item)
		}
		out = append(out, s)
	}
	return out
}

func asOrderIDs(t *testing.T, value interface{}) map[string]struct{} {
	t.Helper()
	orders, ok := value.([]interface{})
	if !ok {
		t.Fatalf("expected []interface{} orders payload, got %#v", value)
	}

	ids := make(map[string]struct{}, len(orders))
	for _, orderVal := range orders {
		order, ok := orderVal.(map[string]interface{})
		if !ok {
			t.Fatalf("expected order object, got %#v", orderVal)
		}
		id, _ := order["$id"].(string)
		if id == "" {
			t.Fatalf("expected order id in payload, got %#v", order)
		}
		ids[id] = struct{}{}
	}

	return ids
}

func containsString(values []string, want string) bool {
	for _, value := range values {
		if value == want {
			return true
		}
	}
	return false
}

func TestAdminGetOrder(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	registerAdminOrderRoutes(te)

	te.SeedUser("cust_1", map[string]interface{}{
		"name":  "Alice Customer",
		"phone": "+919999999999",
		"email": "alice@example.com",
		"role":  "customer",
	})
	te.FakeAW.SeedDocument("addresses", "addr_1", map[string]interface{}{
		"user_id":      "cust_1",
		"full_address": "221B Baker Street",
		"city":         "Bengaluru",
		"latitude":     12.9831,
		"longitude":    77.6401,
	})
	te.SeedOrder("order_1", map[string]interface{}{
		"order_number":        "CHZ-1001",
		"customer_id":         "cust_1",
		"delivery_address_id": "addr_1",
		"restaurant_id":       "rest_1",
		"restaurant_name":     "Test Restaurant",
		"status":              "placed",
		"placed_at":           time.Now().UTC().Format(time.RFC3339),
	})

	rec := te.AuthRequest("GET", "/api/v1/admin/orders/order_1", nil, "admin_1", "admin")
	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	resp := te.ParseResponse(rec)
	data, ok := resp["data"].(map[string]interface{})
	if !ok {
		t.Fatalf("expected response data object, got %#v", resp["data"])
	}

	if got := data["order_number"]; got != "CHZ-1001" {
		t.Errorf("expected order_number=CHZ-1001, got %v", got)
	}
	if got := data["customer_name"]; got != "Alice Customer" {
		t.Errorf("expected customer_name=Alice Customer, got %v", got)
	}
	if got := data["customer_phone"]; got != "+919999999999" {
		t.Errorf("expected customer_phone=+919999999999, got %v", got)
	}
	if got := data["customer_email"]; got != "alice@example.com" {
		t.Errorf("expected customer_email=alice@example.com, got %v", got)
	}
	if got := data["delivery_address_line"]; got != "221B Baker Street" {
		t.Errorf("expected delivery_address_line=221B Baker Street, got %v", got)
	}
	if got := data["delivery_city"]; got != "Bengaluru" {
		t.Errorf("expected delivery_city=Bengaluru, got %v", got)
	}
	if got := data["delivery_latitude"]; got != 12.9831 {
		t.Errorf("expected delivery_latitude=12.9831, got %v", got)
	}
	if got := data["delivery_longitude"]; got != 77.6401 {
		t.Errorf("expected delivery_longitude=77.6401, got %v", got)
	}
}

func TestAdminGetOrder_MissingLinkedDocsFallback(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	registerAdminOrderRoutes(te)

	te.SeedOrder("order_2", map[string]interface{}{
		"order_number":        "CHZ-1002",
		"customer_id":         "missing_customer",
		"delivery_address_id": "missing_address",
		"restaurant_id":       "rest_1",
		"restaurant_name":     "Test Restaurant",
		"status":              "placed",
		"placed_at":           time.Now().UTC().Format(time.RFC3339),
	})

	rec := te.AuthRequest("GET", "/api/v1/admin/orders/order_2", nil, "admin_1", "admin")
	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	resp := te.ParseResponse(rec)
	data, ok := resp["data"].(map[string]interface{})
	if !ok {
		t.Fatalf("expected response data object, got %#v", resp["data"])
	}

	if got := data["order_number"]; got != "CHZ-1002" {
		t.Errorf("expected order_number=CHZ-1002, got %v", got)
	}
	if got := data["customer_id"]; got != "missing_customer" {
		t.Errorf("expected customer_id=missing_customer, got %v", got)
	}
	if _, exists := data["customer_name"]; exists {
		t.Errorf("expected customer_name to be absent when linked user is missing, got %v", data["customer_name"])
	}
	if _, exists := data["delivery_address_line"]; exists {
		t.Errorf("expected delivery_address_line to be absent when linked address is missing, got %v", data["delivery_address_line"])
	}
}

func TestAdminStuckOrdersPreview(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	registerAdminOrderRoutes(te)

	now := time.Now().UTC()
	stale := now.Add(-4 * time.Hour).Format(time.RFC3339)
	fresh := now.Add(-20 * time.Minute).Format(time.RFC3339)

	te.SeedOrder("order_delivered_stale", map[string]interface{}{
		"status":    "delivered",
		"placed_at": stale,
	})
	te.SeedOrder("order_cancelled_stale", map[string]interface{}{
		"status":    "cancelled",
		"placed_at": stale,
	})
	te.SeedOrder("order_placed_stale", map[string]interface{}{
		"status":    "placed",
		"placed_at": stale,
	})
	te.SeedOrder("order_delivered_fresh", map[string]interface{}{
		"status":    "delivered",
		"placed_at": fresh,
	})

	rec := te.AuthRequest(
		"GET",
		"/api/v1/admin/orders/stuck/preview?statuses=delivered,cancelled,placed&min_age_minutes=60&per_page=50",
		nil,
		"admin_1",
		"admin",
	)
	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	resp := te.ParseResponse(rec)
	data, ok := resp["data"].(map[string]interface{})
	if !ok {
		t.Fatalf("expected response data object, got %#v", resp["data"])
	}

	if got := asInt(t, data["eligible_count"]); got != 2 {
		t.Fatalf("expected eligible_count=2, got %d", got)
	}

	filters, ok := data["filters"].(map[string]interface{})
	if !ok {
		t.Fatalf("expected filters object, got %#v", data["filters"])
	}

	blockedStatuses := asStringSlice(t, filters["blocked_statuses"])
	if !containsString(blockedStatuses, "placed") {
		t.Fatalf("expected blocked statuses to include placed, got %#v", blockedStatuses)
	}

	effectiveStatuses := asStringSlice(t, filters["effective_statuses"])
	if !(containsString(effectiveStatuses, "delivered") && containsString(effectiveStatuses, "cancelled")) {
		t.Fatalf("expected effective statuses to include delivered and cancelled, got %#v", effectiveStatuses)
	}

	ids := asOrderIDs(t, data["orders"])
	if _, ok := ids["order_delivered_stale"]; !ok {
		t.Fatal("expected stale delivered order in preview results")
	}
	if _, ok := ids["order_cancelled_stale"]; !ok {
		t.Fatal("expected stale cancelled order in preview results")
	}
	if _, ok := ids["order_placed_stale"]; ok {
		t.Fatal("expected stale placed order to be excluded from preview candidates")
	}
	if _, ok := ids["order_delivered_fresh"]; ok {
		t.Fatal("expected fresh delivered order to be excluded from preview candidates")
	}
}

func TestAdminDeleteStuckOrders(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	registerAdminOrderRoutes(te)

	now := time.Now().UTC()
	stale := now.Add(-5 * time.Hour).Format(time.RFC3339)
	fresh := now.Add(-15 * time.Minute).Format(time.RFC3339)

	te.SeedOrder("order_delivered_stale", map[string]interface{}{
		"status":    "delivered",
		"placed_at": stale,
	})
	te.SeedOrder("order_cancelled_stale", map[string]interface{}{
		"status":    "cancelled",
		"placed_at": stale,
	})
	te.SeedOrder("order_placed_stale", map[string]interface{}{
		"status":    "placed",
		"placed_at": stale,
	})
	te.SeedOrder("order_cancelled_fresh", map[string]interface{}{
		"status":    "cancelled",
		"placed_at": fresh,
	})

	body := map[string]interface{}{
		"statuses":        []string{"delivered", "cancelled", "placed"},
		"min_age_minutes": 60,
		"limit":           50,
	}

	rec := te.AuthRequest("POST", "/api/v1/admin/orders/stuck/delete", body, "admin_1", "admin")
	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	resp := te.ParseResponse(rec)
	data, ok := resp["data"].(map[string]interface{})
	if !ok {
		t.Fatalf("expected response data object, got %#v", resp["data"])
	}

	assertions := map[string]int{
		"eligible_count": 2,
		"blocked_count":  1,
		"deleted_count":  2,
		"failed_count":   0,
		"examined_count": 3,
	}
	for key, want := range assertions {
		if got := asInt(t, data[key]); got != want {
			t.Fatalf("expected %s=%d, got %d", key, want, got)
		}
	}

	blockedOrders, ok := data["blocked_orders"].([]interface{})
	if !ok {
		t.Fatalf("expected blocked_orders list, got %#v", data["blocked_orders"])
	}
	if len(blockedOrders) != 1 {
		t.Fatalf("expected 1 blocked order detail, got %d", len(blockedOrders))
	}
	blockedOrder, ok := blockedOrders[0].(map[string]interface{})
	if !ok {
		t.Fatalf("expected blocked order object, got %#v", blockedOrders[0])
	}
	if got := fmt.Sprintf("%v", blockedOrder["order_id"]); got != "order_placed_stale" {
		t.Fatalf("expected blocked order id order_placed_stale, got %s", got)
	}

	if doc := te.FakeAW.GetDocument("orders", "order_delivered_stale"); doc != nil {
		t.Fatal("expected stale delivered order to be hard-deleted")
	}
	if doc := te.FakeAW.GetDocument("orders", "order_cancelled_stale"); doc != nil {
		t.Fatal("expected stale cancelled order to be hard-deleted")
	}
	if doc := te.FakeAW.GetDocument("orders", "order_placed_stale"); doc == nil {
		t.Fatal("expected stale placed order to remain due to blocked status")
	}
	if doc := te.FakeAW.GetDocument("orders", "order_cancelled_fresh"); doc == nil {
		t.Fatal("expected fresh cancelled order to remain because it is not stale")
	}
}
