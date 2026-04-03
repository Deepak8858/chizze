package handlers_test

import (
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
	admin.GET("/orders/:id", adminHandler.GetOrder)
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
