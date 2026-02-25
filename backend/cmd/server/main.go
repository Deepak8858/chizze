package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"runtime"
	"syscall"
	"time"

	"github.com/chizze/backend/internal/config"
	"github.com/chizze/backend/internal/handlers"
	"github.com/chizze/backend/internal/middleware"
	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/internal/websocket"
	"github.com/chizze/backend/internal/workers"
	"github.com/chizze/backend/pkg/appwrite"
	redispkg "github.com/chizze/backend/pkg/redis"
	"github.com/gin-gonic/gin"

	_ "github.com/chizze/backend/docs" // swagger generated docs
	swaggerFiles "github.com/swaggo/files"
	ginSwagger "github.com/swaggo/gin-swagger"
)

// @title           Chizze Food Delivery API
// @version         1.0
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
	log.Printf("  Chizze API Server v1.0.0")
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

	// ─── Initialize Handlers ───
	authHandler := handlers.NewAuthHandler(awService, redisClient, cfg)
	userHandler := handlers.NewUserHandler(awService, cacheService)
	restaurantHandler := handlers.NewRestaurantHandler(awService, geoService, cacheService)
	menuHandler := handlers.NewMenuHandler(awService, cacheService)
	orderHandler := handlers.NewOrderHandler(awService, orderService, geoService, redisClient, broadcaster)
	paymentHandler := handlers.NewPaymentHandler(awService, paymentService)
	deliveryHandler := handlers.NewDeliveryHandler(awService, geoService, redisClient, broadcaster)
	reviewHandler := handlers.NewReviewHandler(awService)
	couponHandler := handlers.NewCouponHandler(awService, cacheService)
	notifHandler := handlers.NewNotificationHandler(awService)
	partnerHandler := handlers.NewPartnerHandler(awService)
	favoriteHandler := handlers.NewFavoriteHandler(awService)
	goldHandler := handlers.NewGoldHandler(awService)
	referralHandler := handlers.NewReferralHandler(awService)
	scheduledOrderHandler := handlers.NewScheduledOrderHandler(awService)

	// ─── Create Router ───
	r := gin.New()

	// Global middleware — order matters
	r.Use(middleware.Security())          // Request ID + security headers (first)
	r.Use(middleware.OtelGin("chizze-api")) // OpenTelemetry request tracing
	r.Use(middleware.Logger())            // Structured logging with request ID
	r.Use(gin.Recovery())                 // Panic recovery
	r.Use(middleware.CORS(cfg))           // CORS
	r.Use(middleware.MaxBodySize(2 << 20)) // 2MB max request body
	r.Use(middleware.Gzip())                                // Response compression
	r.Use(middleware.RedisRateLimit(redisClient, 200, 500)) // 200 req/s, burst 500 (Redis-backed)

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
			"status":         statusText,
			"service":        "chizze-api",
			"version":        version,
			"uptime":         time.Since(startTime).String(),
			"checks":         checks,
			"circuit_breaker": awClient.BreakerState().String(),
		})
	})

	// ─── Swagger UI ───
	r.GET("/swagger/*any", ginSwagger.WrapHandler(swaggerFiles.Handler))

	// ─── API v1 Routes ───
	v1 := r.Group("/api/v1")

	// Auth (public) — stricter rate limit
	auth := v1.Group("/auth")
	auth.Use(middleware.RedisRateLimit(redisClient, 10, 20)) // 10 req/s for auth (Redis-backed)
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
	partner.Use(middleware.RequireRole("restaurant_owner"))
	{
		// Dashboard & Analytics
		partner.GET("/dashboard", partnerHandler.Dashboard)
		partner.GET("/analytics", partnerHandler.Analytics)
		partner.GET("/performance", partnerHandler.Performance)

		// Restaurant status
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
		partner.POST("/reviews/:id/reply", reviewHandler.ReplyToReview)
	}

	// ─── Delivery Routes (delivery_partner) ───
	delivery := v1.Group("/delivery")
	delivery.Use(middleware.Auth(cfg, redisClient))
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
		delivery.PUT("/orders/:id/status", orderHandler.UpdateStatus)
		delivery.GET("/orders", deliveryHandler.ActiveOrders)
		delivery.GET("/payouts", deliveryHandler.ListPayouts)
		delivery.POST("/payouts/request", deliveryHandler.RequestPayout)
	}

	// Webhooks (no auth — validated by signature)
	v1.POST("/payments/webhook", paymentHandler.Webhook)

	// ─── Start Background Workers ───
	workerCtx, workerCancel := context.WithCancel(context.Background())

	deliveryMatcher := workers.NewDeliveryMatcher(awService, geoService, redisClient, hub, 15*time.Second)
	go deliveryMatcher.Start(workerCtx)

	orderTimeout := workers.NewOrderTimeout(awService, hub, 30*time.Second, 5*time.Minute)
	go orderTimeout.Start(workerCtx)

	scheduledOrderProcessor := workers.NewScheduledOrderProcessor(awService, hub, 30*time.Second)
	go scheduledOrderProcessor.Start(workerCtx)

	notificationDispatcher := workers.NewNotificationDispatcher(awService, hub, redisClient, 10*time.Second)
	go notificationDispatcher.Start(workerCtx)

	log.Printf("🔧 4 background workers started")

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
var version = "1.0.0"
