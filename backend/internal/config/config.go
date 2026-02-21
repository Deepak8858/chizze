package config

import (
	"log"
	"os"
	"strconv"
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
	RazorpayKeyID        string
	RazorpayKeySecret    string
	RazorpayWebhookSecret string

	// Redis
	RedisURL string

	// JWT
	JWTSecret string

	// CORS
	AllowedOrigins string

	// Environment
	GinMode string

	// Performance
	RequestTimeout time.Duration
	MaxConnections int
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
		Port:               getEnv("PORT", "8080"),
		AppwriteEndpoint:   getEnv("APPWRITE_ENDPOINT", "https://sgp.cloud.appwrite.io/v1"),
		AppwriteProjectID:    getEnv("APPWRITE_PROJECT_ID", ""),
		AppwriteAPIKey:       getEnv("APPWRITE_API_KEY", ""),
		AppwriteDatabaseID:   getEnv("APPWRITE_DATABASE_ID", "chizze_db"),
		RazorpayKeyID:        getEnv("RAZORPAY_KEY_ID", ""),
		RazorpayKeySecret:    getEnv("RAZORPAY_KEY_SECRET", ""),
		RazorpayWebhookSecret: getEnv("RAZORPAY_WEBHOOK_SECRET", ""),
		RedisURL:           getEnv("REDIS_URL", "redis://:Dream%408858@165.232.177.81:6379"),
		JWTSecret:          getEnv("JWT_SECRET", "chizze-dev-secret"),
		AllowedOrigins:     getEnv("ALLOWED_ORIGINS", "*"),
		GinMode:            getEnv("GIN_MODE", "debug"),
		RequestTimeout:     time.Duration(timeout) * time.Second,
		MaxConnections:     maxConns,
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

	return cfg
}

func getEnv(key, fallback string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	return fallback
}
