package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"runtime"
	"strings"
	"syscall"
	"time"

	"github.com/chizze/backend/internal/config"
	"github.com/chizze/backend/internal/handlers"
	"github.com/chizze/backend/internal/middleware"
	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/internal/websocket"
	"github.com/chizze/backend/internal/workers"
	"github.com/chizze/backend/pkg/appwrite"
	"github.com/chizze/backend/pkg/fcm"
	redispkg "github.com/chizze/backend/pkg/redis"
	"github.com/gin-gonic/gin"

	_ "github.com/chizze/backend/docs" // swagger generated docs
	swaggerFiles "github.com/swaggo/files"
	ginSwagger "github.com/swaggo/gin-swagger"
)

// @title           Chizze Food Delivery API
// @version         1.2
// @description     Backend API for Chizze — a food delivery platform with customer, restaurant partner, and delivery partner roles.
// @termsOfService  https://chizze.app/terms

// @contact.name   Chizze Support
// @contact.url    https://chizze.app/support
// @contact.email  support@chizze.app

// @license.name  Proprietary
// @license.url   https://chizze.app/license

// @host      api.devdeepak.me
// @BasePath  /api/v1

// @securityDefinitions.apikey BearerAuth
// @in header
// @name Authorization
// @description Enter "Bearer {token}"

func main() {
	// ─── Load Config ───
	cfg := config.Load()
	gin.SetMode(cfg.GinMode)

	// ─── Startup Info ───
	log.Printf("═══════════════════════════════════════")
	log.Printf("  Chizze API Server v%s", version)
	log.Printf("  Mode: %s | Port: %s", cfg.GinMode, cfg.Port)
	log.Printf("  GOMAXPROCS: %d | CPUs: %d", runtime.GOMAXPROCS(0), runtime.NumCPU())
	log.Printf("  Appwrite: %s", cfg.AppwriteEndpoint)
	log.Printf("  Timeout: %v | MaxConns: %d", cfg.RequestTimeout, cfg.MaxConnections)
	log.Printf("═══════════════════════════════════════")

	// ─── Initialize Tracing ───
	tracingCtx := context.Background()
	shutdownTracing, err := middleware.InitTracing(tracingCtx, "chizze-api", version)
	if err != nil {
		log.Printf("WARNING: Tracing init failed (non-fatal): %v", err)
	} else {
		log.Printf("OpenTelemetry tracing initialized")
	}

	// ─── Initialize Clients ───
	awClient := appwrite.NewClient(cfg)

	// ─── Initialize Redis ───
	redisClient, err := redispkg.NewClient(cfg.RedisURL)
	if err != nil {
		log.Fatalf("FATAL: Redis connection failed: %v", err)
	}
	// Note: Redis is closed explicitly in the graceful shutdown block below

	// ─── Schema Drift Check ───
	// Verifies the Appwrite collections have every attribute the code writes.
	// Runs in the background so a slow Appwrite call doesn't delay server start.
	go services.ValidateCollectionSchemas(awClient)

	// ─── Initialize Services ───
	awService := services.NewAppwriteService(awClient)
	orderService := services.NewOrderService(awService)
	paymentService := services.NewPaymentService(cfg)
	geoService := services.NewGeoService()
	cacheService := services.NewCacheService(redisClient)

	// ─── Initialize WebSocket Hub ───
	hub := websocket.NewHub()
	go hub.Run()
	broadcaster := websocket.NewEventBroadcaster(hub)

	// Route inbound WebSocket messages (chat between customer ↔ rider ↔ restaurant).
	// The handler validates the sender is a participant of the order before
	// forwarding the message to the counterparty, so chat can't be used to
	// deliver arbitrary payloads to arbitrary users.
	hub.SetIncomingHandler(handlers.NewChatRouter(awService, broadcaster))

	// ─── Initialize Handlers ───
	authHandler := handlers.NewAuthHandler(awService, redisClient, cfg)
	userHandler := handlers.NewUserHandler(awService, cacheService)
	restaurantHandler := handlers.NewRestaurantHandler(awService, geoService, cacheService)
	menuHandler := handlers.NewMenuHandler(awService, cacheService)
	orderHandler := handlers.NewOrderHandler(awService, orderService, geoService, redisClient, broadcaster)
	paymentHandler := handlers.NewPaymentHandler(awService, paymentService)
	deliveryHandler := handlers.NewDeliveryHandler(awService, geoService, redisClient, broadcaster)
	reviewHandler := handlers.NewReviewHandler(awService, broadcaster)
	couponHandler := handlers.NewCouponHandler(awService, cacheService)
	notifHandler := handlers.NewNotificationHandler(awService)
	partnerHandler := handlers.NewPartnerHandler(awService, redisClient)
	favoriteHandler := handlers.NewFavoriteHandler(awService)
	goldHandler := handlers.NewGoldHandler(awService)
	referralHandler := handlers.NewReferralHandler(awService)
	scheduledOrderHandler := handlers.NewScheduledOrderHandler(awService)
	adminHandler := handlers.NewAdminHandler(awService, redisClient, hub)

	// ─── Create Router ───
	r := gin.New()

	// Global middleware — order matters
	r.Use(middleware.Security())                            // Request ID + security headers (first)
	r.Use(middleware.OtelGin("chizze-api"))                 // OpenTelemetry request tracing
	r.Use(middleware.Logger())                              // Structured logging with request ID
	r.Use(gin.Recovery())                                   // Panic recovery
	r.Use(middleware.CORS(cfg))                             // CORS
	r.Use(middleware.MaxBodySize(2 << 20))                  // 2MB max request body
	r.Use(middleware.Gzip())                                // Response compression
	// Per-IP rate limit (sliding 1s window, 2000 req/s per IP). Raised from
	// 500 to accommodate 1000 concurrent users behind NAT/corporate gateways
	// where many legitimate clients share a single egress IP. 500/s tipped
	// a load test into 429 storms for the shared-IP case; 2000 gives headroom
	// without meaningfully weakening abuse protection (the per-user limit
	// still bounds individual accounts).
	r.Use(middleware.RedisRateLimit(redisClient, 2000, 2000))

	// Health check — liveness probe (always 200 if server is running)
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status":  "ok",
			"service": "chizze-api",
			"version": version,
			"uptime":  time.Since(startTime).String(),
		})
	})

	// Readiness probe — checks all dependencies
	r.GET("/health/ready", func(c *gin.Context) {
		checks := make(map[string]string)
		allOk := true

		// Check Redis
		if err := redisClient.Ping(c.Request.Context()); err != nil {
			checks["redis"] = "error: " + err.Error()
			allOk = false
		} else {
			checks["redis"] = "ok"
		}

		// Check Appwrite (lightweight health call)
		awHealthCtx, awCancel := context.WithTimeout(c.Request.Context(), 3*time.Second)
		defer awCancel()
		if err := awClient.Health(awHealthCtx); err != nil {
			checks["appwrite"] = "error: " + err.Error()
			allOk = false
		} else {
			checks["appwrite"] = "ok"
		}

		status := http.StatusOK
		statusText := "ready"
		if !allOk {
			status = http.StatusServiceUnavailable
			statusText = "degraded"
		}

		c.JSON(status, gin.H{
			"status":          statusText,
			"service":         "chizze-api",
			"version":         version,
			"uptime":          time.Since(startTime).String(),
			"checks":          checks,
			"circuit_breaker": awClient.BreakerState().String(),
		})
	})

	// Android App Links verification endpoints.
	// Keep this on the API domain so Play Console can validate autoVerify hosts.
	androidAppPackage := strings.TrimSpace(cfg.AndroidAppPackage)
	assetLinkFingerprints := make([]string, 0, len(cfg.AndroidAssetLinksFingerprints))
	for _, fp := range cfg.AndroidAssetLinksFingerprints {
		trimmed := strings.TrimSpace(fp)
		if trimmed != "" {
			assetLinkFingerprints = append(assetLinkFingerprints, trimmed)
		}
	}

	if androidAppPackage != "" && len(assetLinkFingerprints) > 0 {
		assetLinksPayload := []gin.H{
			{
				"relation": []string{"delegate_permission/common.handle_all_urls"},
				"target": gin.H{
					"namespace":                "android_app",
					"package_name":             androidAppPackage,
					"sha256_cert_fingerprints": assetLinkFingerprints,
				},
			},
		}

		r.GET("/.well-known/assetlinks.json", func(c *gin.Context) {
			c.Header("Cache-Control", "public, max-age=300")
			c.JSON(http.StatusOK, assetLinksPayload)
		})
		r.GET("/assetlinks.json", func(c *gin.Context) {
			c.Header("Cache-Control", "public, max-age=300")
			c.JSON(http.StatusOK, assetLinksPayload)
		})
	} else {
		log.Printf("WARNING: Android App Links endpoints disabled: ANDROID_APP_PACKAGE=%q fingerprints=%d", androidAppPackage, len(assetLinkFingerprints))
	}

	// ─── Swagger UI (dev only) ───
	if cfg.GinMode != "release" {
		r.GET("/swagger/*any", ginSwagger.WrapHandler(swaggerFiles.Handler))
	}

	// ─── API v1 Routes ───
	v1 := r.Group("/api/v1")

	// Auth (public) — stricter rate limit. 30 req/s per IP is enough for
	// concurrent signups from a shared NAT but still throttles brute force.
	// Per-phone OTP rate limit (3 per 10min) is enforced inside SendOTP.
	auth := v1.Group("/auth")
	auth.Use(middleware.RedisRateLimit(redisClient, 30, 30))
	{
		auth.POST("/send-otp", authHandler.SendOTP)
		auth.POST("/verify-otp", authHandler.VerifyOTP)
		auth.POST("/exchange", authHandler.Exchange)
		auth.POST("/check-phone", authHandler.CheckPhone)
	}

	// Restaurants (public)
	restaurants := v1.Group("/restaurants")
	{
		restaurants.GET("", restaurantHandler.List)
		restaurants.GET("/nearby", restaurantHandler.Nearby)
		restaurants.GET("/:id", restaurantHandler.GetDetail)
		restaurants.GET("/:id/menu", restaurantHandler.GetMenu)
		restaurants.GET("/:id/reviews", restaurantHandler.GetReviews)
	}

	// Coupons (public)
	v1.GET("/coupons", couponHandler.ListAvailable)

	// ─── Authenticated Routes ───
	authenticated := v1.Group("")
	authenticated.Use(middleware.Auth(cfg, redisClient))
	// Per-user rate limit: a single authenticated account cannot exceed 100
	// requests per second regardless of how many IPs they spread across.
	// Protects the order/menu/WS endpoints from runaway clients and script abuse.
	authenticated.Use(middleware.PerUserRateLimit(redisClient, 100))
	{
		// WebSocket
		authenticated.GET("/ws", func(c *gin.Context) {
			websocket.ServeWs(hub, c)
		})

		// Auth (authenticated)
		authenticated.POST("/auth/refresh", authHandler.Refresh)
		authenticated.DELETE("/auth/logout", authHandler.Logout)
		authenticated.POST("/auth/onboard", authHandler.Onboard)

		// Users
		users := authenticated.Group("/users")
		{
			users.GET("/me", userHandler.GetProfile)
			users.PUT("/me", userHandler.UpdateProfile)
			users.GET("/me/addresses", userHandler.ListAddresses)
			users.POST("/me/addresses", userHandler.CreateAddress)
			users.PUT("/me/addresses/:id", userHandler.UpdateAddress)
			users.DELETE("/me/addresses/:id", userHandler.DeleteAddress)
			users.PUT("/me/fcm-token", userHandler.UpdateFCMToken)
		}

		// Orders
		orders := authenticated.Group("/orders")
		{
			orders.POST("", orderHandler.PlaceOrder)
			orders.GET("", orderHandler.ListOrders)
			orders.GET("/:id", orderHandler.GetOrder)
			orders.GET("/:id/tracking", orderHandler.GetTracking)
			orders.PUT("/:id/cancel", orderHandler.CancelOrder)
			orders.POST("/:id/review", reviewHandler.CreateReview)
		}

		// Cart / Coupons
		authenticated.POST("/cart/validate-coupon", couponHandler.Validate)

		// Payments
		payments := authenticated.Group("/payments")
		{
			payments.POST("/initiate", paymentHandler.Initiate)
			payments.POST("/verify", paymentHandler.Verify)
		}

		// Notifications
		notifs := authenticated.Group("/notifications")
		{
			notifs.GET("", notifHandler.List)
			notifs.PUT("/:id/read", notifHandler.MarkRead)
			notifs.PUT("/read-all", notifHandler.MarkAllRead)
		}

		// App content & settings
		authenticated.GET("/content/banners", adminHandler.ListAppBanners)
		authenticated.GET("/settings", adminHandler.GetSettings)

		// Favorites
		users.GET("/me/favorites", favoriteHandler.List)
		users.POST("/me/favorites", favoriteHandler.Add)
		users.DELETE("/me/favorites/:restaurant_id", favoriteHandler.Remove)

		// Gold Membership
		gold := authenticated.Group("/gold")
		{
			gold.GET("/plans", goldHandler.GetPlans)
			gold.GET("/status", goldHandler.GetStatus)
			gold.POST("/subscribe", goldHandler.Subscribe)
			gold.PUT("/cancel", goldHandler.Cancel)
		}

		// Referrals
		referrals := authenticated.Group("/referrals")
		{
			referrals.GET("/code", referralHandler.GetCode)
			referrals.POST("/apply", referralHandler.Apply)
			referrals.GET("", referralHandler.ListReferrals)
		}

		// Scheduled Orders
		orders.GET("/scheduled", scheduledOrderHandler.List)
		orders.POST("/scheduled", scheduledOrderHandler.Create)
		orders.PUT("/scheduled/:id/cancel", scheduledOrderHandler.Cancel)
	}

	// ─── Partner Routes (restaurant_owner) ───
	partner := v1.Group("/partner")
	partner.Use(middleware.Auth(cfg, redisClient))
	partner.Use(middleware.PerUserRateLimit(redisClient, 100))
	partner.Use(middleware.RequireRole("restaurant_owner"))
	{
		// Dashboard & Analytics
		partner.GET("/dashboard", partnerHandler.Dashboard)
		partner.GET("/analytics", partnerHandler.Analytics)
		partner.GET("/performance", partnerHandler.Performance)

		// Restaurant
		partner.PUT("/restaurant", partnerHandler.UpdateRestaurant)
		partner.PUT("/restaurant/status", partnerHandler.ToggleOnline)

		// Orders
		partner.GET("/orders", partnerHandler.ListOrders)
		partner.PUT("/orders/:id/status", orderHandler.UpdateStatus)

		// Menu items
		partner.GET("/menu", menuHandler.ListItems)
		partner.POST("/menu", menuHandler.CreateItem)
		partner.PUT("/menu/:id", menuHandler.UpdateItem)
		partner.DELETE("/menu/:id", menuHandler.DeleteItem)

		// Menu categories
		partner.GET("/categories", partnerHandler.ListCategories)
		partner.POST("/categories", partnerHandler.CreateCategory)
		partner.PUT("/categories/:id", partnerHandler.UpdateCategory)
		partner.DELETE("/categories/:id", partnerHandler.DeleteCategory)

		// Reviews
		partner.GET("/reviews", partnerHandler.ListReviews)
		partner.POST("/reviews/:id/reply", reviewHandler.ReplyToReview)

		// Bank details & payouts
		partner.GET("/bank-details", partnerHandler.GetBankDetails)
		partner.PUT("/bank-details", partnerHandler.UpdateBankDetails)
		partner.GET("/payouts", partnerHandler.ListPayouts)
		partner.POST("/payouts/request", partnerHandler.RequestPayout)
	}

	// ─── Delivery Routes (delivery_partner) ───
	// Higher per-user limit (200/s) because rider apps ping location frequently.
	delivery := v1.Group("/delivery")
	delivery.Use(middleware.Auth(cfg, redisClient))
	delivery.Use(middleware.PerUserRateLimit(redisClient, 200))
	delivery.Use(middleware.RequireRole("delivery_partner"))
	{
		delivery.GET("/dashboard", deliveryHandler.Dashboard)
		delivery.GET("/earnings", deliveryHandler.Earnings)
		delivery.GET("/performance", deliveryHandler.Performance)
		delivery.GET("/profile", deliveryHandler.GetProfile)
		delivery.PUT("/profile", deliveryHandler.UpdateProfile)
		delivery.PUT("/status", deliveryHandler.ToggleOnline)
		delivery.PUT("/location", deliveryHandler.UpdateLocation)
		delivery.PUT("/orders/:id/accept", deliveryHandler.AcceptOrder)
		delivery.PUT("/orders/:id/reject", deliveryHandler.RejectOrder)
		delivery.POST("/orders/:id/report", deliveryHandler.ReportIssue)
		delivery.PUT("/orders/:id/status", orderHandler.UpdateStatus)
		delivery.GET("/orders", deliveryHandler.ActiveOrders)
		delivery.GET("/payouts", deliveryHandler.ListPayouts)
		delivery.POST("/payouts/request", deliveryHandler.RequestPayout)
	}

	// ─── Admin Routes (admin / super_admin only) ───
	admin := v1.Group("/admin")
	admin.Use(middleware.Auth(cfg, redisClient))
	admin.Use(middleware.RequireRole("admin", "super_admin"))
	{
		// Dashboard & Analytics
		admin.GET("/dashboard", adminHandler.Dashboard)
		admin.GET("/analytics", adminHandler.Analytics)
		admin.GET("/analytics/sla", adminHandler.AnalyticsSLA)
		admin.GET("/analytics/items", adminHandler.AnalyticsItems)
		admin.GET("/analytics/cities", adminHandler.AnalyticsCities)
		admin.GET("/analytics/retention", adminHandler.AnalyticsRetention)
		admin.GET("/analytics/revenue", adminHandler.AnalyticsRevenue)
		admin.GET("/reports/financial", adminHandler.ReportsFinancial)
		admin.GET("/reports/cancellations", adminHandler.ReportsCancellations)
		admin.GET("/leaderboards", adminHandler.Leaderboards)

		// Users
		admin.GET("/users", adminHandler.ListUsers)
		admin.GET("/users/:id", adminHandler.GetUser)
		admin.PUT("/users/:id", adminHandler.UpdateUser)
		admin.DELETE("/users/:id", adminHandler.DeleteUser)

		// Restaurants
		admin.GET("/restaurants", adminHandler.ListRestaurants)
		admin.GET("/restaurants/pending", adminHandler.PendingRestaurants)
		admin.GET("/restaurants/:id", adminHandler.GetRestaurant)
		admin.GET("/restaurants/:id/menu", adminHandler.GetRestaurantMenu)
		admin.PUT("/restaurants/:id", adminHandler.UpdateRestaurant)
		admin.PUT("/restaurants/:id/approve", adminHandler.ApproveRestaurant)
		admin.PUT("/restaurants/:id/reject", adminHandler.RejectRestaurant)
		admin.DELETE("/restaurants/:id", adminHandler.DeleteRestaurant)

		// Orders
		admin.GET("/orders", adminHandler.ListOrders)
		admin.GET("/orders/active", adminHandler.ActiveOrders)
		admin.GET("/orders/stuck/preview", adminHandler.PreviewStuckOrders)
		admin.POST("/orders/stuck/delete", adminHandler.DeleteStuckOrders)
		admin.GET("/orders/:id", adminHandler.GetOrder)
		admin.PUT("/orders/:id/cancel", adminHandler.CancelOrder)
		admin.PUT("/orders/:id/reassign", adminHandler.ReassignOrder)

		// Delivery Partners
		admin.GET("/delivery-partners", adminHandler.ListDeliveryPartners)
		admin.GET("/delivery-partners/pending", adminHandler.PendingDeliveryPartners)
		admin.GET("/delivery-partners/:id", adminHandler.GetDeliveryPartner)
		admin.PUT("/delivery-partners/:id", adminHandler.UpdateDeliveryPartner)
		admin.PUT("/delivery-partners/:id/verify", adminHandler.VerifyDeliveryPartner)
		admin.GET("/delivery-partners/:id/payouts", adminHandler.DeliveryPartnerPayouts)

		// Payouts
		admin.GET("/payouts", adminHandler.ListPayouts)
		admin.PUT("/payouts/:id", adminHandler.UpdatePayout)

		// Coupons
		admin.GET("/coupons", adminHandler.ListCoupons)
		admin.POST("/coupons", adminHandler.CreateCoupon)
		admin.PUT("/coupons/:id", adminHandler.UpdateCoupon)
		admin.DELETE("/coupons/:id", adminHandler.DeleteCoupon)

		// Reviews
		admin.GET("/reviews", adminHandler.ListReviews)
		admin.PUT("/reviews/:id", adminHandler.UpdateReview)
		admin.DELETE("/reviews/:id", adminHandler.DeleteReview)

		// Gold
		admin.GET("/gold/subscriptions", adminHandler.ListGoldSubscriptions)
		admin.GET("/gold/stats", adminHandler.GoldStats)

		// Referrals
		admin.GET("/referrals", adminHandler.ListReferrals)
		admin.GET("/referrals/stats", adminHandler.ReferralStats)

		// Notifications
		admin.POST("/notifications/broadcast", adminHandler.BroadcastNotification)
		admin.GET("/notifications/history", adminHandler.NotificationHistory)

		// Disputes
		admin.GET("/disputes", adminHandler.ListDisputes)
		admin.GET("/disputes/:id", adminHandler.GetDispute)
		admin.PUT("/disputes/:id", adminHandler.UpdateDispute)

		// Admin Accounts
		admin.GET("/admins", adminHandler.ListAdmins)
		admin.POST("/admins", adminHandler.CreateAdmin)
		admin.PUT("/admins/:id", adminHandler.UpdateAdmin)
		admin.DELETE("/admins/:id", adminHandler.DeleteAdmin)

		// Live
		admin.GET("/live/sessions", adminHandler.LiveSessions)
		admin.GET("/live/stats", adminHandler.LiveStats)
		admin.GET("/live/riders", adminHandler.LiveRiders)
		admin.GET("/live/orders", adminHandler.LiveOrders)

		// Zones
		admin.GET("/zones", adminHandler.ListZones)
		admin.POST("/zones", adminHandler.CreateZone)
		admin.PUT("/zones/:id", adminHandler.UpdateZone)
		admin.DELETE("/zones/:id", adminHandler.DeleteZone)

		// Surge
		admin.GET("/surge", adminHandler.ListSurge)
		admin.POST("/surge", adminHandler.CreateSurge)
		admin.PUT("/surge/:id", adminHandler.UpdateSurge)
		admin.DELETE("/surge/:id", adminHandler.DeleteSurge)

		// Feature Flags
		admin.GET("/feature-flags", adminHandler.ListFeatureFlags)
		admin.PUT("/feature-flags/:key", adminHandler.UpdateFeatureFlag)

		// Audit Log
		admin.GET("/audit-log", adminHandler.ListAuditLog)

		// Support
		admin.GET("/support/issues", adminHandler.ListSupportIssues)
		admin.GET("/support/issues/:id", adminHandler.GetSupportIssue)
		admin.PUT("/support/issues/:id", adminHandler.UpdateSupportIssue)
		admin.GET("/support/issues/:id/messages", adminHandler.SupportIssueMessages)
		admin.POST("/support/issues/:id/reply", adminHandler.ReplySupportIssue)

		// Content
		admin.GET("/content/banners", adminHandler.ListBanners)
		admin.POST("/content/banners/upload", adminHandler.UploadBannerImage)
		admin.POST("/content/banners", adminHandler.CreateBanner)
		admin.PUT("/content/banners/:id", adminHandler.UpdateBanner)
		admin.DELETE("/content/banners/:id", adminHandler.DeleteBanner)
		admin.GET("/content/categories", adminHandler.ListContentCategories)

		// Settings
		admin.GET("/settings", adminHandler.GetSettings)
		admin.PUT("/settings", adminHandler.UpdateSettings)
	}

	// Webhooks (no auth — validated by signature)
	v1.POST("/payments/webhook", paymentHandler.Webhook)

	// ─── Start Background Workers ───
	workerCtx, workerCancel := context.WithCancel(context.Background())

	// FCM client for push notifications (HTTP v1 API via Firebase Admin SDK).
	// Legacy FCM_SERVER_KEY is ignored — Google decommissioned that endpoint
	// on 2024-06-20. Set FIREBASE_CREDENTIALS_JSON + FIREBASE_PROJECT_ID
	// to enable push delivery to backgrounded/killed apps.
	if cfg.FCMServerKey != "" {
		log.Printf("[startup] WARNING: FCM_SERVER_KEY is set but ignored — the legacy FCM API was shut down on 2024-06-20. Set FIREBASE_CREDENTIALS_JSON + FIREBASE_PROJECT_ID instead.")
	}
	fcmClient := fcm.NewClient(cfg.FirebaseCredentialsJSON, cfg.FirebaseProjectID)
	if fcmClient != nil {
		log.Printf("[startup] FCM push notifications enabled (HTTP v1)")
	} else {
		log.Printf("[startup] FCM disabled — set FIREBASE_CREDENTIALS_JSON (service-account path) and FIREBASE_PROJECT_ID to enable push to backgrounded users")
	}

	// Wire FCM into AppwriteService so every CreateNotification call also fires
	// a push, ensuring Android tray notifications reach users whose app is
	// backgrounded or whose WS channel has dropped.
	awService.SetFCMClient(fcmClient)

	// Wire FCM + hub into OrderHandler so PlaceOrder can wake a backgrounded
	// restaurant owner with a push notification (prior to this fix, a dead WS
	// meant new orders were silently dropped and auto-cancelled in 5 min).
	orderHandler.SetPushDependencies(hub, fcmClient)

	// 8s interval: with 10s pending_rider TTL, same rider gets the order
	// re-sent within 10-18s if they don't respond (Bug Fix: was 15s + 20s = 35s)
	deliveryMatcher := workers.NewDeliveryMatcher(awService, geoService, redisClient, hub, 8*time.Second, fcmClient)

	// ── Startup: Clear stale Redis delivery state ──
	// The busy_riders and pending_riders SETS have no TTL. If the server crashed
	// or a delivery was never properly completed, riders stay marked as busy/pending
	// forever — the matcher permanently skips them. Clear everything on startup so
	// all online riders get a fresh start.
	if redisClient != nil {
		cleanupCtx := context.Background()
		redisClient.Del(cleanupCtx, "busy_riders")
		redisClient.Del(cleanupCtx, "pending_riders")
		// Also clear any stale per-order pending locks and per-rider pending keys
		// These have TTLs but clearing them on startup avoids ghost locks from the
		// previous server instance.
		rdb := redisClient.GetRedis()
		iter := rdb.Scan(cleanupCtx, 0, "pending_delivery:*", 100).Iterator()
		for iter.Next(cleanupCtx) {
			rdb.Del(cleanupCtx, iter.Val())
		}
		iter = rdb.Scan(cleanupCtx, 0, "pending_rider:*", 100).Iterator()
		for iter.Next(cleanupCtx) {
			rdb.Del(cleanupCtx, iter.Val())
		}
		log.Println("[startup] Cleared stale Redis delivery state (busy_riders, pending_riders, pending_delivery:*, pending_rider:*)")
	}

	go deliveryMatcher.Start(workerCtx)

	// Wire instant matching: when UpdateStatus sets an order to "ready", the
	// matcher runs immediately instead of waiting for the next 15-second tick.
	orderHandler.SetMatcherCallback(func() {
		deliveryMatcher.Process(context.Background())
	})
	// Also re-run matching instantly when a rider rejects, so the next
	// eligible rider receives the request without waiting for the ticker.
	deliveryHandler.SetMatcherCallback(func() {
		deliveryMatcher.Process(context.Background())
	})

	// 10-minute timeout (was 5m): restaurants on flaky connections or with
	// tablets that sleep briefly deserve grace — 5m caused false-cancels of
	// orders the partner app was about to pick up.
	orderTimeout := workers.NewOrderTimeout(awService, hub, redisClient, 30*time.Second, 10*time.Minute)
	go orderTimeout.Start(workerCtx)

	scheduledOrderProcessor := workers.NewScheduledOrderProcessor(awService, hub, 30*time.Second)
	go scheduledOrderProcessor.Start(workerCtx)

	// Fan out to 4 dispatcher workers — a single BRPOP loop becomes the
	// bottleneck once the Appwrite write + FCM round-trip inside processQueue
	// exceeds the interval between queued notifications (observed at ~1k
	// active users during peak order bursts).
	for i := 0; i < 4; i++ {
		nd := workers.NewNotificationDispatcher(awService, hub, redisClient, 10*time.Second)
		go nd.Start(workerCtx)
	}

	log.Printf("🔧 background workers started (dispatcher x4)")

	// ─── Start Server with Production Settings ───
	srv := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           r,
		ReadTimeout:       15 * time.Second,
		ReadHeaderTimeout: 5 * time.Second, // Prevent slowloris
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       120 * time.Second,
		MaxHeaderBytes:    1 << 20, // 1MB max headers
	}

	go func() {
		log.Printf("🚀 Chizze API listening on :%s", cfg.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server failed: %v", err)
		}
	}()

	// ─── Graceful Shutdown ───
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	fmt.Println("\n🛑 Shutting down server...")

	// Cancel workers first
	workerCancel()
	log.Println("Workers signaled to stop")

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Fatal("Server forced shutdown:", err)
	}
	if err := redisClient.Close(); err != nil {
		log.Printf("Redis close error: %v", err)
	}
	if shutdownTracing != nil {
		if err := shutdownTracing(ctx); err != nil {
			log.Printf("Tracing shutdown error: %v", err)
		}
	}
	fmt.Println("✅ Server stopped gracefully")
}

var startTime = time.Now()

// version is set at build time via -ldflags
var version = "1.2.0"
