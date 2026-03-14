package workers_test

import (
	"context"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/chizze/backend/internal/config"
	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/internal/testutil"
	"github.com/chizze/backend/internal/websocket"
	"github.com/chizze/backend/internal/workers"
	"github.com/chizze/backend/pkg/appwrite"
	redispkg "github.com/chizze/backend/pkg/redis"
	"github.com/redis/go-redis/v9"
)

// newMatcherEnv creates a DeliveryMatcher with test dependencies.
func newMatcherEnv(t *testing.T) (*workers.DeliveryMatcher, *testutil.FakeAppwrite, *miniredis.Miniredis, *redispkg.Client) {
	t.Helper()
	fakeAW := testutil.NewFakeAppwrite()
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("miniredis: %v", err)
	}

	cfg := &config.Config{
		AppwriteEndpoint:   fakeAW.Server.URL,
		AppwriteProjectID:  "test",
		AppwriteAPIKey:     "test",
		AppwriteDatabaseID: "test_db",
		RequestTimeout:     5 * time.Second,
	}
	awClient := appwrite.NewClient(cfg)
	awService := services.NewAppwriteService(awClient)
	geoService := services.NewGeoService()
	redisClient, err := redispkg.NewClient("redis://" + mr.Addr())
	if err != nil {
		t.Fatalf("redis: %v", err)
	}

	hub := websocket.NewHub()
	go hub.Run()

	matcher := workers.NewDeliveryMatcher(awService, geoService, redisClient, hub, 15*time.Second)

	return matcher, fakeAW, mr, redisClient
}

func TestDeliveryMatcher_FindsReadyOrders(t *testing.T) {
	matcher, fakeAW, mr, redisClient := newMatcherEnv(t)
	defer fakeAW.Close()
	defer mr.Close()

	// Seed restaurant
	fakeAW.SeedDocument("restaurants", "rest_1", map[string]interface{}{
		"owner_id":  "owner_1",
		"name":      "Test Restaurant",
		"latitude":  12.97,
		"longitude": 77.59,
	})

	// Seed customer + address
	fakeAW.SeedDocument("users", "cust_1", map[string]interface{}{
		"name": "Customer", "phone": "+919876543210",
	})
	fakeAW.SeedDocument("addresses", "addr_1", map[string]interface{}{
		"user_id": "cust_1", "full_address": "123 Test St",
		"latitude": 12.98, "longitude": 77.60,
	})

	// Seed a ready order (delivery_partner_id absent = null)
	fakeAW.SeedDocument("orders", "order_ready", map[string]interface{}{
		"status":              "ready",
		"restaurant_id":       "rest_1",
		"customer_id":         "cust_1",
		"delivery_address_id": "addr_1",
		"delivery_fee":        40.0,
		"tip":                 10.0,
		"order_number":        "CHZ-200",
		"item_total":          500.0,
	})

	// Seed a placed order (should not be matched)
	fakeAW.SeedDocument("orders", "order_placed", map[string]interface{}{
		"status":        "placed",
		"restaurant_id": "rest_1",
		"customer_id":   "cust_1",
		"order_number":  "CHZ-201",
	})

	// Add a rider near the restaurant in Redis geo set
	ctx := context.Background()
	redisClient.GeoAdd(ctx, "rider_locations", &redis.GeoLocation{
		Name: "rider_1", Longitude: 77.59, Latitude: 12.97,
	})

	matcher.Process(ctx)

	// Delivery request should be created for the ready order
	reqCount := fakeAW.DocumentCount("delivery_requests")
	if reqCount != 1 {
		t.Errorf("expected 1 delivery request, got %d", reqCount)
	}

	// pending_delivery lock should be set
	if !mr.Exists("pending_delivery:order_ready") {
		t.Error("expected pending_delivery lock to be set")
	}
}

func TestDeliveryMatcher_RespectsLock(t *testing.T) {
	matcher, fakeAW, mr, _ := newMatcherEnv(t)
	defer fakeAW.Close()
	defer mr.Close()

	fakeAW.SeedDocument("restaurants", "rest_1", map[string]interface{}{
		"latitude": 12.97, "longitude": 77.59, "name": "R",
	})
	fakeAW.SeedDocument("orders", "order_locked", map[string]interface{}{
		"status": "ready", "restaurant_id": "rest_1", "customer_id": "c1", "order_number": "CHZ-300",
	})

	// Pre-set lock
	mr.Set("pending_delivery:order_locked", "1")
	mr.SetTTL("pending_delivery:order_locked", 2*time.Minute)

	matcher.Process(context.Background())

	// No delivery request should be created (order locked)
	if fakeAW.DocumentCount("delivery_requests") != 0 {
		t.Error("expected no delivery request for locked order")
	}
}

func TestDeliveryMatcher_FiltersRejectedRiders(t *testing.T) {
	matcher, fakeAW, mr, redisClient := newMatcherEnv(t)
	defer fakeAW.Close()
	defer mr.Close()

	fakeAW.SeedDocument("restaurants", "rest_1", map[string]interface{}{
		"latitude": 12.97, "longitude": 77.59, "name": "R",
	})
	fakeAW.SeedDocument("users", "cust_1", map[string]interface{}{"name": "C"})
	fakeAW.SeedDocument("addresses", "addr_1", map[string]interface{}{
		"user_id": "cust_1", "full_address": "Test", "latitude": 12.98, "longitude": 77.60,
	})
	fakeAW.SeedDocument("orders", "order_r", map[string]interface{}{
		"status": "ready", "restaurant_id": "rest_1", "customer_id": "cust_1",
		"delivery_address_id": "addr_1", "delivery_fee": 30.0, "tip": 0.0, "order_number": "CHZ-301",
	})

	ctx := context.Background()

	// Add two riders near the restaurant
	redisClient.GeoAdd(ctx, "rider_locations",
		&redis.GeoLocation{Name: "rider_A", Longitude: 77.59, Latitude: 12.97},
		&redis.GeoLocation{Name: "rider_B", Longitude: 77.591, Latitude: 12.971},
	)

	// Mark rider_A as having rejected this order
	redisClient.SAdd(ctx, "rejected_riders:order_r", "rider_A")

	matcher.Process(ctx)

	// Delivery request should target rider_B (not rider_A)
	docs := fakeAW.AllDocuments("delivery_requests")
	if len(docs) != 1 {
		t.Fatalf("expected 1 delivery request, got %d", len(docs))
	}
	if docs[0]["rider_id"] != "rider_B" {
		t.Errorf("expected rider_id=rider_B, got %v", docs[0]["rider_id"])
	}
}

func TestDeliveryMatcher_NoNearbyRiders(t *testing.T) {
	matcher, fakeAW, mr, _ := newMatcherEnv(t)
	defer fakeAW.Close()
	defer mr.Close()

	fakeAW.SeedDocument("restaurants", "rest_1", map[string]interface{}{
		"latitude": 12.97, "longitude": 77.59, "name": "R",
	})
	fakeAW.SeedDocument("orders", "order_no_riders", map[string]interface{}{
		"status": "ready", "restaurant_id": "rest_1", "customer_id": "c1", "order_number": "CHZ-302",
	})

	// No riders in geo set
	matcher.Process(context.Background())

	// No delivery requests created
	if fakeAW.DocumentCount("delivery_requests") != 0 {
		t.Error("expected no delivery requests when no riders nearby")
	}

	// Lock should be cleaned up
	if mr.Exists("pending_delivery:order_no_riders") {
		t.Error("expected pending_delivery lock to be cleaned up")
	}
}

func TestDeliveryMatcher_AllRidersRejected(t *testing.T) {
	matcher, fakeAW, mr, redisClient := newMatcherEnv(t)
	defer fakeAW.Close()
	defer mr.Close()

	fakeAW.SeedDocument("restaurants", "rest_1", map[string]interface{}{
		"latitude": 12.97, "longitude": 77.59, "name": "R",
	})
	fakeAW.SeedDocument("orders", "order_all_rej", map[string]interface{}{
		"status": "ready", "restaurant_id": "rest_1", "customer_id": "c1", "order_number": "CHZ-303",
	})

	ctx := context.Background()
	redisClient.GeoAdd(ctx, "rider_locations",
		&redis.GeoLocation{Name: "rider_A", Longitude: 77.59, Latitude: 12.97},
	)

	// All riders rejected
	redisClient.SAdd(ctx, "rejected_riders:order_all_rej", "rider_A")

	matcher.Process(ctx)

	if fakeAW.DocumentCount("delivery_requests") != 0 {
		t.Error("expected no delivery requests when all riders rejected")
	}

	// Lock should be cleared for retry on next cycle
	if mr.Exists("pending_delivery:order_all_rej") {
		t.Error("expected pending_delivery lock to be cleared for retry")
	}
}

func TestDeliveryMatcher_CalculatesEarning(t *testing.T) {
	matcher, fakeAW, mr, redisClient := newMatcherEnv(t)
	defer fakeAW.Close()
	defer mr.Close()

	fakeAW.SeedDocument("restaurants", "rest_1", map[string]interface{}{
		"latitude": 12.97, "longitude": 77.59, "name": "R",
	})
	fakeAW.SeedDocument("users", "cust_1", map[string]interface{}{"name": "C"})
	fakeAW.SeedDocument("addresses", "addr_1", map[string]interface{}{
		"user_id": "cust_1", "full_address": "Test", "latitude": 12.98, "longitude": 77.60,
	})
	fakeAW.SeedDocument("orders", "order_earn", map[string]interface{}{
		"status": "ready", "restaurant_id": "rest_1", "customer_id": "cust_1",
		"delivery_address_id": "addr_1", "delivery_fee": 40.0, "tip": 10.0,
		"order_number": "CHZ-304", "item_total": 300.0,
	})

	ctx := context.Background()
	redisClient.GeoAdd(ctx, "rider_locations",
		&redis.GeoLocation{Name: "rider_1", Longitude: 77.59, Latitude: 12.97},
	)

	matcher.Process(ctx)

	docs := fakeAW.AllDocuments("delivery_requests")
	if len(docs) != 1 {
		t.Fatalf("expected 1 delivery request, got %d", len(docs))
	}

	earning, _ := docs[0]["estimated_earning"].(float64)
	if earning != 50.0 {
		t.Errorf("expected estimated_earning=50 (40+10), got %v", earning)
	}
}
