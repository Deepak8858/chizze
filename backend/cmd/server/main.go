package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/chizze/backend/internal/config"
	"github.com/chizze/backend/internal/handlers"
	"github.com/chizze/backend/internal/middleware"
	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/pkg/appwrite"
	"github.com/gin-gonic/gin"
)

func main() {
	// ─── Load Config ───
	cfg := config.Load()
	gin.SetMode(cfg.GinMode)

	// ─── Initialize Clients ───
	awClient := appwrite.NewClient(cfg)

	// ─── Initialize Services ───
	awService := services.NewAppwriteService(awClient)
	orderService := services.NewOrderService(awService)
	paymentService := services.NewPaymentService(cfg)
	geoService := services.NewGeoService()

	// ─── Initialize Handlers ───
	authHandler := handlers.NewAuthHandler(awService)
	userHandler := handlers.NewUserHandler(awService)
	restaurantHandler := handlers.NewRestaurantHandler(awService, geoService)
	menuHandler := handlers.NewMenuHandler(awService)
	orderHandler := handlers.NewOrderHandler(awService, orderService)
	paymentHandler := handlers.NewPaymentHandler(awService, paymentService)
	deliveryHandler := handlers.NewDeliveryHandler(awService, geoService)
	reviewHandler := handlers.NewReviewHandler(awService)
	couponHandler := handlers.NewCouponHandler(awService)
	notifHandler := handlers.NewNotificationHandler(awService)

	// ─── Create Router ───
	r := gin.New()
	r.Use(middleware.Logger())
	r.Use(gin.Recovery())
	r.Use(middleware.CORS(cfg))
	r.Use(middleware.RateLimit(100, 200)) // 100 req/s, burst 200

	// Health check
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status":  "ok",
			"service": "chizze-api",
			"version": "1.0.0",
		})
	})

	// ─── API v1 Routes ───
	v1 := r.Group("/api/v1")

	// Auth (public)
	auth := v1.Group("/auth")
	{
		auth.POST("/send-otp", authHandler.SendOTP)
		auth.POST("/verify-otp", authHandler.VerifyOTP)
		auth.POST("/refresh", authHandler.Refresh)
		auth.DELETE("/logout", authHandler.Logout)
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
	authenticated.Use(middleware.Auth(cfg))
	{
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
	partner.Use(middleware.Auth(cfg))
	partner.Use(middleware.RequireRole("restaurant_owner"))
	{
		partner.GET("/menu", menuHandler.ListItems)
		partner.POST("/menu", menuHandler.CreateItem)
		partner.PUT("/menu/:id", menuHandler.UpdateItem)
		partner.DELETE("/menu/:id", menuHandler.DeleteItem)

		partner.PUT("/orders/:id/status", orderHandler.UpdateStatus)
		partner.POST("/reviews/:id/reply", reviewHandler.ReplyToReview)
	}

	// ─── Delivery Routes (delivery_partner) ───
	delivery := v1.Group("/delivery")
	delivery.Use(middleware.Auth(cfg))
	delivery.Use(middleware.RequireRole("delivery_partner"))
	{
		delivery.PUT("/status", deliveryHandler.ToggleOnline)
		delivery.PUT("/location", deliveryHandler.UpdateLocation)
		delivery.PUT("/orders/:id/accept", deliveryHandler.AcceptOrder)
		delivery.PUT("/orders/:id/status", orderHandler.UpdateStatus)
	}

	// Webhooks (no auth — validated by signature)
	v1.POST("/payments/webhook", paymentHandler.Webhook)

	// ─── Start Server ───
	srv := &http.Server{
		Addr:         ":" + cfg.Port,
		Handler:      r,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	go func() {
		log.Printf("🚀 Chizze API starting on port %s", cfg.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server failed: %v", err)
		}
	}()

	// ─── Graceful Shutdown ───
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	fmt.Println("\n🛑 Shutting down server...")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Fatal("Server forced shutdown:", err)
	}
	fmt.Println("✅ Server stopped gracefully")
}
