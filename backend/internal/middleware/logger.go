package middleware

import (
	"log"
	"time"

	"github.com/gin-gonic/gin"
)

// Logger middleware logs request details with request ID for production tracing
func Logger() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		path := c.Request.URL.Path
		method := c.Request.Method
		query := c.Request.URL.RawQuery

		c.Next()

		latency := time.Since(start)
		status := c.Writer.Status()
		clientIP := c.ClientIP()
		size := c.Writer.Size()
		reqID, _ := c.Get("requestId")

		// Log level based on status code
		if status >= 500 {
			log.Printf("ERROR [%s] %s %s %s | %d | %v | %s | %d bytes",
				reqID, method, path, query, status, latency, clientIP, size)
		} else if status >= 400 {
			log.Printf("WARN  [%s] %s %s %s | %d | %v | %s | %d bytes",
				reqID, method, path, query, status, latency, clientIP, size)
		} else {
			log.Printf("INFO  [%s] %s %s %s | %d | %v | %s | %d bytes",
				reqID, method, path, query, status, latency, clientIP, size)
		}
	}
}
