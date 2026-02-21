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
	"github.com/chizze/backend/pkg/appwrite"
	redispkg "github.com/chizze/backend/pkg/redis"
	"github.com/gin-gonic/gin"
)

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

	// ─── Initialize Clients ───
	awClient := appwrite.NewClient(cfg)

	// ─── Initialize Redis ───
	redisClient, err := redispkg.NewClient(cfg.RedisURL)
	if err != nil {
		log.Fatalf("FATAL: Redis connection failed: %v", err)
	}
	defer redisClient.Close()

	// ─── Initialize Services ───
	awService := services.NewAppwriteService(awClient)
	orderService := services.NewOrderService(awService)
	paymentService := services.NewPaymentService(cfg)
	geoService := services.NewGeoService()

	// ─── Initialize Handlers ───
	authHandler := handlers.NewAuthHandler(awService, redisClient, cfg)
	userHandler := handlers.NewUserHandler(awService)
	restaurantHandler := handlers.NewRestaurantHandler(awService, geoService)
	menuHandler := handlers.NewMenuHandler(awService)
	orderHandler := handlers.NewOrderHandler(awService, orderService, geoService, redisClient)
	paymentHandler := handlers.NewPaymentHandler(awService, paymentService)
	deliveryHandler := handlers.NewDeliveryHandler(awService, geoService, redisClient)
	reviewHandler := handlers.NewReviewHandler(awService)
	couponHandler := handlers.NewCouponHandler(awService)
	notifHandler := handlers.NewNotificationHandler(awService)
	partnerHandler := handlers.NewPartnerHandler(awService)

	// ─── Create Router ───
	r := gin.New()

	// Global middleware — order matters
	r.Use(middleware.Security())          // Request ID + security headers (first)
	r.Use(middleware.Logger())            // Structured logging with request ID
	r.Use(gin.Recovery())                 // Panic recovery
	r.Use(middleware.CORS(cfg))           // CORS
	r.Use(middleware.MaxBodySize(2 << 20)) // 2MB max request body
	r.Use(middleware.Gzip())                                // Response compression
	r.Use(middleware.RedisRateLimit(redisClient, 200, 500)) // 200 req/s, burst 500 (Redis-backed)

	// Health check (no auth, no rate limit)
	r.GET("/health", func(c *gin.Context) {
		redisStatus := "ok"
		if err := redisClient.Ping(c.Request.Context()); err != nil {
			redisStatus = "error: " + err.Error()
		}
		c.JSON(http.StatusOK, gin.H{
			"status":  "ok",
			"service": "chizze-api",
			"version": "1.0.0",
			"uptime":  time.Since(startTime).String(),
			"redis":   redisStatus,
		})
	})

	// ─── API v1 Routes ───
	v1 := r.Group("/api/v1")

	// Auth (public) — stricter rate limit
	auth := v1.Group("/auth")
	auth.Use(middleware.RedisRateLimit(redisClient, 10, 20)) // 10 req/s for auth (Redis-backed)
	{
		auth.POST("/send-otp", authHandler.SendOTP)
		auth.POST("/verify-otp", authHandler.VerifyOTP)
		auth.POST("/exchange", authHandler.Exchange)
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
		// Auth (authenticated)
		authenticated.POST("/auth/refresh", authHandler.Refresh)
		authenticated.DELETE("/auth/logout", authHandler.Logout)

		// Users
		users := authenticated.Group("/users")
		{
			users.GET("/me", userHandler.GetProfile)
			users.PUT("/me", userHandler.UpdateProfile)
			users.GET("/me/addresses", userHandler.ListAddresses)
			users.POST("/me/addresses", userHandler.CreateAddress)
			users.PUT("/me/addresses/:id", userHandler.UpdateAddress)
			users.DELETE("/me/addresses/:id", userHandler.DeleteAddress)
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
		delivery.PUT("/status", deliveryHandler.ToggleOnline)
		delivery.PUT("/location", deliveryHandler.UpdateLocation)
		delivery.PUT("/orders/:id/accept", deliveryHandler.AcceptOrder)
		delivery.PUT("/orders/:id/status", orderHandler.UpdateStatus)
		delivery.GET("/orders", deliveryHandler.ActiveOrders)
	}

	// Webhooks (no auth — validated by signature)
	v1.POST("/payments/webhook", paymentHandler.Webhook)

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
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Fatal("Server forced shutdown:", err)
	}
	if err := redisClient.Close(); err != nil {
		log.Printf("Redis close error: %v", err)
	}
	fmt.Println("✅ Server stopped gracefully")
}

var startTime = time.Now()
