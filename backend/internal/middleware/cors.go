package middleware

import (
	"strings"

	"github.com/chizze/backend/internal/config"
	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
)

// CORS returns configured CORS middleware
func CORS(cfg *config.Config) gin.HandlerFunc {
	origins := strings.Split(cfg.AllowedOrigins, ",")

	// CORS spec: AllowCredentials=true requires explicit origins, not "*"
	allowCreds := true
	for _, o := range origins {
		if strings.TrimSpace(o) == "*" {
			allowCreds = false
			break
		}
	}

	return cors.New(cors.Config{
		AllowOrigins:     origins,
		AllowMethods:     []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Authorization", "X-Request-ID", "X-Idempotency-Key"},
		ExposeHeaders:    []string{"Content-Length", "X-Request-ID"},
		AllowCredentials: allowCreds,
		MaxAge:           12 * 3600, // Preflight cache 12h
	})
}
