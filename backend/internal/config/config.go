package config

import (
	"log"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/joho/godotenv"
)

// Config holds all application configuration
type Config struct {
	Port string

	// Appwrite
	AppwriteEndpoint   string
	AppwriteProjectID  string
	AppwriteAPIKey     string
	AppwriteDatabaseID string

	// Razorpay
	RazorpayKeyID         string
	RazorpayKeySecret     string
	RazorpayWebhookSecret string

	// Redis
	RedisURL string

	// JWT
	JWTSecret string

	// FCM Push Notifications
	FCMServerKey string

	// CORS
	AllowedOrigins string

	// Environment
	GinMode string

	// Performance
	RequestTimeout time.Duration
	MaxConnections int

	// Android App Links
	AndroidAppPackage             string
	AndroidAssetLinksFingerprints []string
}

// IsProduction returns true if running in release mode
func (c *Config) IsProduction() bool {
	return c.GinMode == "release"
}

// Load reads configuration from environment variables
func Load() *Config {
	// Load .env if present (development)
	if err := godotenv.Load(); err != nil {
		log.Println("No .env file found, using system environment variables")
	}

	timeout, _ := strconv.Atoi(getEnv("REQUEST_TIMEOUT_SECONDS", "15"))
	maxConns, _ := strconv.Atoi(getEnv("MAX_CONNECTIONS", "200"))

	cfg := &Config{
		Port:                  getEnv("PORT", "8080"),
		AppwriteEndpoint:      getEnv("APPWRITE_ENDPOINT", "https://sgp.cloud.appwrite.io/v1"),
		AppwriteProjectID:     getEnv("APPWRITE_PROJECT_ID", ""),
		AppwriteAPIKey:        getEnv("APPWRITE_API_KEY", ""),
		AppwriteDatabaseID:    getEnv("APPWRITE_DATABASE_ID", "chizze_db"),
		RazorpayKeyID:         getEnv("RAZORPAY_KEY_ID", ""),
		RazorpayKeySecret:     getEnv("RAZORPAY_KEY_SECRET", ""),
		RazorpayWebhookSecret: getEnv("RAZORPAY_WEBHOOK_SECRET", ""),
		FCMServerKey:          getEnv("FCM_SERVER_KEY", ""),
		RedisURL:              getEnv("REDIS_URL", "redis://localhost:6379"),
		JWTSecret:             getEnv("JWT_SECRET", "chizze-dev-secret"),
		AllowedOrigins:        getEnv("ALLOWED_ORIGINS", "*"),
		GinMode:               getEnv("GIN_MODE", "debug"),
		RequestTimeout:        time.Duration(timeout) * time.Second,
		MaxConnections:        maxConns,
		AndroidAppPackage:     getEnv("ANDROID_APP_PACKAGE", "com.chizze.app"),
		AndroidAssetLinksFingerprints: parseCSV(getEnv(
			"ANDROID_ASSETLINKS_SHA256_FINGERPRINTS",
			"EE:38:5E:00:9F:8B:C1:99:EB:BC:4C:7C:4E:5A:D4:BA:5D:C2:DC:17:E9:64:5A:E8:C7:02:6A:DA:81:CF:F3:EB",
		)),
	}

	// Validate required keys
	if cfg.AppwriteAPIKey == "" {
		if cfg.IsProduction() {
			log.Fatal("FATAL: APPWRITE_API_KEY not set in production mode")
		}
		log.Println("WARNING: APPWRITE_API_KEY not set — Appwrite calls will fail")
	}

	if cfg.IsProduction() && cfg.JWTSecret == "chizze-dev-secret" {
		log.Fatal("FATAL: JWT_SECRET must be changed from default in production mode")
	}

	if cfg.IsProduction() && cfg.RedisURL == "redis://localhost:6379" {
		log.Fatal("FATAL: REDIS_URL must be set to a real Redis instance in production mode")
	}

	// Validate Razorpay credentials — empty secret causes 401 on every payment attempt
	if cfg.RazorpayKeyID == "" {
		if cfg.IsProduction() {
			log.Fatal("FATAL: RAZORPAY_KEY_ID not set — client checkout cannot start")
		}
		log.Println("WARNING: RAZORPAY_KEY_ID not set — Razorpay checkout will fail")
	}

	if cfg.RazorpayKeySecret == "" {
		if cfg.IsProduction() {
			log.Fatal("FATAL: RAZORPAY_KEY_SECRET not set — all payments will fail with 401")
		}
		log.Println("WARNING: RAZORPAY_KEY_SECRET not set — Razorpay payments will fail")
	}

	if cfg.IsProduction() && strings.HasPrefix(cfg.RazorpayKeyID, "rzp_test_") {
		log.Println("WARNING: Razorpay TEST keys detected in production — real payments will NOT be processed")
	}
	if cfg.IsProduction() && cfg.RazorpayWebhookSecret == "" {
		log.Println("WARNING: RAZORPAY_WEBHOOK_SECRET not set — webhook signatures cannot be verified in production")
	}

	if len(cfg.AndroidAssetLinksFingerprints) == 0 {
		log.Println("WARNING: ANDROID_ASSETLINKS_SHA256_FINGERPRINTS is empty — App Links verification will fail")
	}

	return cfg
}

func getEnv(key, fallback string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	return fallback
}

func parseCSV(value string) []string {
	parts := strings.Split(value, ",")
	result := make([]string, 0, len(parts))
	seen := make(map[string]struct{}, len(parts))

	for _, part := range parts {
		trimmed := strings.TrimSpace(part)
		if trimmed == "" {
			continue
		}
		if _, ok := seen[trimmed]; ok {
			continue
		}
		seen[trimmed] = struct{}{}
		result = append(result, trimmed)
	}

	return result
}
