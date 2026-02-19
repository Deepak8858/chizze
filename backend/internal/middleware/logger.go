package middleware

import (
	"log"
	"time"

	"github.com/gin-gonic/gin"
)

// Logger middleware logs request method, path, status, and latency
func Logger() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		path := c.Request.URL.Path
		method := c.Request.Method

		c.Next()

		latency := time.Since(start)
		status := c.Writer.Status()
		clientIP := c.ClientIP()

		log.Printf("[%s] %s %s | %d | %v | %s",
			method, path, c.Request.URL.RawQuery,
			status, latency, clientIP,
		)
	}
}
