package testutil

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/chizze/backend/internal/config"
	"github.com/chizze/backend/internal/handlers"
	"github.com/chizze/backend/internal/middleware"
	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/internal/websocket"
	"github.com/chizze/backend/pkg/appwrite"
	redispkg "github.com/chizze/backend/pkg/redis"
	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/redis/go-redis/v9"
)

const (
	TestJWTSecret = "test-secret-for-unit-tests"
	TestDBID      = "test_db"
)

// TestEnv bundles all test infrastructure: fake Appwrite, miniredis, real
// services, real handlers, and a gin router that mirrors main.go routes.
type TestEnv struct {
	T               *testing.T
	FakeAW          *FakeAppwrite
	MiniRedis       *miniredis.Miniredis
	Config          *config.Config
	AWClient        *appwrite.Client
	AWService       *services.AppwriteService
	OrderService    *services.OrderService
	GeoService      *services.GeoService
	CacheService    *services.CacheService
	RedisClient     *redispkg.Client
	Hub             *websocket.Hub
	Broadcaster     *websocket.EventBroadcaster
	OrderHandler    *handlers.OrderHandler
	DeliveryHandler *handlers.DeliveryHandler
	AuthHandler     *handlers.AuthHandler
	Router          *gin.Engine

	// MatcherCalled is set to true when the matcherCallback fires.
	MatcherCalled bool
}

// NewTestEnv creates a fully wired test environment.
func NewTestEnv(t *testing.T) *TestEnv {
	t.Helper()
	gin.SetMode(gin.TestMode)

	fakeAW := NewFakeAppwrite()

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("miniredis.Run: %v", err)
	}

	cfg := &config.Config{
		Port:               "0",
		AppwriteEndpoint:   fakeAW.Server.URL,
		AppwriteProjectID:  "test_project",
		AppwriteAPIKey:     "test_key",
		AppwriteDatabaseID: TestDBID,
		JWTSecret:          TestJWTSecret,
		RedisURL:           "redis://" + mr.Addr(),
		GinMode:            "test",
		RequestTimeout:     5 * time.Second,
		MaxConnections:     10,
		AllowedOrigins:     "*",
	}

	awClient := appwrite.NewClient(cfg)
	awService := services.NewAppwriteService(awClient)
	orderService := services.NewOrderService(awService)
	geoService := services.NewGeoService()
	redisClient, err := redispkg.NewClient(cfg.RedisURL)
	if err != nil {
		t.Fatalf("redis connect: %v", err)
	}
	cacheService := services.NewCacheService(redisClient)

	hub := websocket.NewHub()
	go hub.Run()
	broadcaster := websocket.NewEventBroadcaster(hub)

	orderHandler := handlers.NewOrderHandler(awService, orderService, geoService, redisClient, broadcaster)
	deliveryHandler := handlers.NewDeliveryHandler(awService, geoService, redisClient, broadcaster)
	authHandler := handlers.NewAuthHandler(awService, redisClient, cfg)

	te := &TestEnv{
		T:               t,
		FakeAW:          fakeAW,
		MiniRedis:       mr,
		Config:          cfg,
		AWClient:        awClient,
		AWService:       awService,
		OrderService:    orderService,
		GeoService:      geoService,
		CacheService:    cacheService,
		RedisClient:     redisClient,
		Hub:             hub,
		Broadcaster:     broadcaster,
		OrderHandler:    orderHandler,
		DeliveryHandler: deliveryHandler,
		AuthHandler:     authHandler,
	}

	// Wire matcher callback so tests can verify it fires.
	orderHandler.SetMatcherCallback(func() {
		te.MatcherCalled = true
	})
	deliveryHandler.SetMatcherCallback(func() {
		te.MatcherCalled = true
	})

	te.SetupRouter()
	return te
}

// Close tears down all test infrastructure.
func (te *TestEnv) Close() {
	te.FakeAW.Close()
	te.MiniRedis.Close()
}

// IssueToken creates a valid Chizze JWT for the given user and role.
func (te *TestEnv) IssueToken(userID, role string) string {
	te.T.Helper()
	claims := middleware.AuthClaims{
		UserID: userID,
		Role:   role,
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    "chizze-api",
			Subject:   userID,
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(1 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	str, err := token.SignedString([]byte(TestJWTSecret))
	if err != nil {
		te.T.Fatalf("IssueToken: %v", err)
	}
	return str
}

// AuthRequest performs an authenticated HTTP request through the router.
func (te *TestEnv) AuthRequest(method, path string, body interface{}, userID, role string) *httptest.ResponseRecorder {
	te.T.Helper()

	var bodyReader *bytes.Buffer
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			te.T.Fatalf("AuthRequest marshal: %v", err)
		}
		bodyReader = bytes.NewBuffer(b)
	} else {
		bodyReader = &bytes.Buffer{}
	}

	req := httptest.NewRequest(method, path, bodyReader)
	req.Header.Set("Content-Type", "application/json")
	if userID != "" {
		token := te.IssueToken(userID, role)
		req.Header.Set("Authorization", "Bearer "+token)
	}

	rec := httptest.NewRecorder()
	te.Router.ServeHTTP(rec, req)
	return rec
}

// MakeRequest creates an HTTP request with auth headers but does not execute it,
// allowing callers to set additional headers (e.g. X-Idempotency-Key).
func (te *TestEnv) MakeRequest(method, path string, body []byte, userID, role string) *http.Request {
	te.T.Helper()
	var bodyReader *bytes.Buffer
	if body != nil {
		bodyReader = bytes.NewBuffer(body)
	} else {
		bodyReader = &bytes.Buffer{}
	}
	req := httptest.NewRequest(method, path, bodyReader)
	req.Header.Set("Content-Type", "application/json")
	if userID != "" {
		token := te.IssueToken(userID, role)
		req.Header.Set("Authorization", "Bearer "+token)
	}
	return req
}

// ServeRequest executes an HTTP request through the router.
func (te *TestEnv) ServeRequest(req *http.Request) *httptest.ResponseRecorder {
	te.T.Helper()
	rec := httptest.NewRecorder()
	te.Router.ServeHTTP(rec, req)
	return rec
}

// Request performs an unauthenticated HTTP request through the router.
func (te *TestEnv) Request(method, path string, body interface{}) *httptest.ResponseRecorder {
	te.T.Helper()

	var bodyReader *bytes.Buffer
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			te.T.Fatalf("Request marshal: %v", err)
		}
		bodyReader = bytes.NewBuffer(b)
	} else {
		bodyReader = &bytes.Buffer{}
	}

	req := httptest.NewRequest(method, path, bodyReader)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	te.Router.ServeHTTP(rec, req)
	return rec
}

// ParseResponse unmarshals the JSON response body.
func (te *TestEnv) ParseResponse(rec *httptest.ResponseRecorder) map[string]interface{} {
	te.T.Helper()
	var result map[string]interface{}
	if err := json.Unmarshal(rec.Body.Bytes(), &result); err != nil {
		te.T.Fatalf("ParseResponse: %v (body: %s)", err, rec.Body.String())
	}
	return result
}

// SetupRouter creates a gin.Engine with routes matching main.go.
func (te *TestEnv) SetupRouter() {
	r := gin.New()
	r.Use(gin.Recovery())

	v1 := r.Group("/api/v1")

	// Auth (public)
	auth := v1.Group("/auth")
	{
		auth.POST("/exchange", te.AuthHandler.Exchange)
		auth.POST("/check-phone", te.AuthHandler.CheckPhone)
		auth.POST("/send-otp", te.AuthHandler.SendOTP)
		auth.POST("/verify-otp", te.AuthHandler.VerifyOTP)
	}

	// Authenticated routes
	authenticated := v1.Group("")
	authenticated.Use(middleware.Auth(te.Config, te.RedisClient))
	{
		authenticated.POST("/auth/refresh", te.AuthHandler.Refresh)
		authenticated.DELETE("/auth/logout", te.AuthHandler.Logout)
		authenticated.POST("/auth/onboard", te.AuthHandler.Onboard)

		orders := authenticated.Group("/orders")
		{
			orders.POST("", te.OrderHandler.PlaceOrder)
			orders.GET("", te.OrderHandler.ListOrders)
			orders.GET("/:id", te.OrderHandler.GetOrder)
			orders.PUT("/:id/cancel", te.OrderHandler.CancelOrder)
		}
	}

	// Partner routes
	partner := v1.Group("/partner")
	partner.Use(middleware.Auth(te.Config, te.RedisClient))
	partner.Use(middleware.RequireRole("restaurant_owner"))
	{
		partner.PUT("/orders/:id/status", te.OrderHandler.UpdateStatus)
	}

	// Delivery routes
	delivery := v1.Group("/delivery")
	delivery.Use(middleware.Auth(te.Config, te.RedisClient))
	delivery.Use(middleware.RequireRole("delivery_partner"))
	{
		delivery.GET("/dashboard", te.DeliveryHandler.Dashboard)
		delivery.PUT("/status", te.DeliveryHandler.ToggleOnline)
		delivery.PUT("/location", te.DeliveryHandler.UpdateLocation)
		delivery.PUT("/orders/:id/accept", te.DeliveryHandler.AcceptOrder)
		delivery.PUT("/orders/:id/reject", te.DeliveryHandler.RejectOrder)
		delivery.PUT("/orders/:id/status", te.OrderHandler.UpdateStatus)
		delivery.GET("/orders", te.DeliveryHandler.ActiveOrders)
		delivery.POST("/orders/:id/report", te.DeliveryHandler.ReportIssue)
		delivery.GET("/earnings", te.DeliveryHandler.Earnings)
		delivery.GET("/performance", te.DeliveryHandler.Performance)
		delivery.GET("/profile", te.DeliveryHandler.GetProfile)
		delivery.PUT("/profile", te.DeliveryHandler.UpdateProfile)
		delivery.GET("/payouts", te.DeliveryHandler.ListPayouts)
		delivery.POST("/payouts/request", te.DeliveryHandler.RequestPayout)
	}

	te.Router = r
}

// ─── Seed Helpers ───

// SeedUser seeds a user document.
func (te *TestEnv) SeedUser(id string, data map[string]interface{}) {
	te.T.Helper()
	te.FakeAW.SeedDocument("users", id, data)
}

// SeedRestaurant seeds a restaurant document.
func (te *TestEnv) SeedRestaurant(id, ownerID string, lat, lng float64, online bool) {
	te.T.Helper()
	te.FakeAW.SeedDocument("restaurants", id, map[string]interface{}{
		"owner_id":  ownerID,
		"name":      "Test Restaurant",
		"address":   "123 Test St",
		"city":      "Bangalore",
		"latitude":  lat,
		"longitude": lng,
		"is_online": online,
		"rating":    4.5,
	})
}

// SeedMenuItem seeds a menu item document.
func (te *TestEnv) SeedMenuItem(id, restaurantID string, price float64) {
	te.T.Helper()
	te.FakeAW.SeedDocument("menu_items", id, map[string]interface{}{
		"restaurant_id": restaurantID,
		"name":          "Test Item " + id,
		"price":         price,
		"is_available":  true,
		"is_veg":        true,
		"category":      "Main Course",
	})
}

// SeedAddress seeds an address document.
func (te *TestEnv) SeedAddress(id, userID string, lat, lng float64) {
	te.T.Helper()
	te.FakeAW.SeedDocument("addresses", id, map[string]interface{}{
		"user_id":      userID,
		"full_address": "456 Test Ave",
		"latitude":     lat,
		"longitude":    lng,
		"type":         "home",
	})
}

// SeedOrder seeds an order document.
func (te *TestEnv) SeedOrder(id string, data map[string]interface{}) {
	te.T.Helper()
	te.FakeAW.SeedDocument("orders", id, data)
}

// SeedDeliveryPartner seeds a delivery partner document.
func (te *TestEnv) SeedDeliveryPartner(id, userID string, online bool, lat, lng float64) {
	te.T.Helper()
	te.FakeAW.SeedDocument("delivery_partners", id, map[string]interface{}{
		"user_id":            userID,
		"is_online":          online,
		"is_on_delivery":     false,
		"rating":             4.5,
		"vehicle_type":       "bike",
		"current_latitude":   lat,
		"current_longitude":  lng,
		"total_deliveries":   0,
		"total_earnings":     0.0,
		"total_ratings":      0,
	})
}

// AddRiderToGeoSet adds a rider to the Redis geo set.
func (te *TestEnv) AddRiderToGeoSet(userID string, lat, lng float64) {
	te.T.Helper()
	ctx := context.Background()
	_, err := te.RedisClient.GeoAdd(ctx, "rider_locations", &redis.GeoLocation{
		Name:      userID,
		Longitude: lng,
		Latitude:  lat,
	})
	if err != nil {
		te.T.Fatalf("AddRiderToGeoSet: %v", err)
	}
}

// SeedCoupon seeds a coupon document.
func (te *TestEnv) SeedCoupon(id string, data map[string]interface{}) {
	te.T.Helper()
	te.FakeAW.SeedDocument("coupons", id, data)
}

// SeedPayout seeds a payout document.
func (te *TestEnv) SeedPayout(id string, data map[string]interface{}) {
	te.T.Helper()
	te.FakeAW.SeedDocument("payouts", id, data)
}
