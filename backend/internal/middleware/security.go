package middleware

import (
	"crypto/rand"
	"encoding/hex"
	"net/http"

	"github.com/gin-gonic/gin"
)

const RequestIDHeader = "X-Request-ID"

// Security adds production security headers and request ID
func Security() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Generate request ID for tracing
		reqID := c.GetHeader(RequestIDHeader)
		if reqID == "" {
			reqID = generateRequestID()
		}
		c.Set("requestId", reqID)
		c.Header(RequestIDHeader, reqID)

		// Security headers
		c.Header("X-Content-Type-Options", "nosniff")
		c.Header("X-Frame-Options", "DENY")
		c.Header("X-XSS-Protection", "1; mode=block")
		c.Header("Referrer-Policy", "strict-origin-when-cross-origin")
		c.Header("Permissions-Policy", "camera=(), microphone=(), geolocation=(self)")

		// HSTS (only effective over HTTPS)
		c.Header("Strict-Transport-Security", "max-age=31536000; includeSubDomains")

		// Prevent caching of API responses
		c.Header("Cache-Control", "no-store, no-cache, must-revalidate")
		c.Header("Pragma", "no-cache")

		c.Next()
	}
}

func generateRequestID() string {
	b := make([]byte, 8)
	rand.Read(b)
	return hex.EncodeToString(b)
}

// MaxBodySize limits request body to the specified number of bytes
func MaxBodySize(maxBytes int64) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, maxBytes)
		c.Next()
	}
}
