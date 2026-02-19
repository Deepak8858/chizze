package config

import (
	"log"
	"os"

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
	RazorpayKeyID     string
	RazorpayKeySecret string

	// Redis
	RedisURL string

	// JWT
	JWTSecret string

	// CORS
	AllowedOrigins string

	// Environment
	GinMode string
}

// Load reads configuration from environment variables
func Load() *Config {
	// Load .env if present (development)
	if err := godotenv.Load(); err != nil {
		log.Println("No .env file found, using system environment variables")
	}

	cfg := &Config{
		Port:               getEnv("PORT", "8080"),
		AppwriteEndpoint:   getEnv("APPWRITE_ENDPOINT", "https://sgp.cloud.appwrite.io/v1"),
		AppwriteProjectID:  getEnv("APPWRITE_PROJECT_ID", "6993347c0006ead7404d"),
		AppwriteAPIKey:     getEnv("APPWRITE_API_KEY", ""),
		AppwriteDatabaseID: getEnv("APPWRITE_DATABASE_ID", "chizze_db"),
		RazorpayKeyID:      getEnv("RAZORPAY_KEY_ID", ""),
		RazorpayKeySecret:  getEnv("RAZORPAY_KEY_SECRET", ""),
		RedisURL:           getEnv("REDIS_URL", "redis://localhost:6379"),
		JWTSecret:          getEnv("JWT_SECRET", "chizze-dev-secret"),
		AllowedOrigins:     getEnv("ALLOWED_ORIGINS", "*"),
		GinMode:            getEnv("GIN_MODE", "debug"),
	}

	// Validate required keys
	if cfg.AppwriteAPIKey == "" {
		log.Println("WARNING: APPWRITE_API_KEY not set — Appwrite calls will fail")
	}

	return cfg
}

func getEnv(key, fallback string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	return fallback
}
