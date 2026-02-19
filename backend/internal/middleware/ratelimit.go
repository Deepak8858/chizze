package middleware

import (
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

// visitor tracks request timestamps per IP
type visitor struct {
	lastSeen time.Time
	tokens   float64
}

// RateLimiter implements a token-bucket rate limiter
type RateLimiter struct {
	mu       sync.RWMutex
	visitors map[string]*visitor
	rate     float64 // tokens per second
	burst    float64 // max tokens
}

// NewRateLimiter creates a rate limiter
func NewRateLimiter(ratePerSec float64, burst int) *RateLimiter {
	rl := &RateLimiter{
		visitors: make(map[string]*visitor),
		rate:     ratePerSec,
		burst:    float64(burst),
	}

	// Cleanup stale visitors every minute
	go func() {
		for {
			time.Sleep(time.Minute)
			rl.cleanup()
		}
	}()

	return rl
}

func (rl *RateLimiter) cleanup() {
	rl.mu.Lock()
	defer rl.mu.Unlock()
	for ip, v := range rl.visitors {
		if time.Since(v.lastSeen) > 3*time.Minute {
			delete(rl.visitors, ip)
		}
	}
}

func (rl *RateLimiter) allow(ip string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	v, exists := rl.visitors[ip]
	now := time.Now()

	if !exists {
		rl.visitors[ip] = &visitor{lastSeen: now, tokens: rl.burst - 1}
		return true
	}

	// Refill tokens based on elapsed time
	elapsed := now.Sub(v.lastSeen).Seconds()
	v.tokens += elapsed * rl.rate
	if v.tokens > rl.burst {
		v.tokens = rl.burst
	}
	v.lastSeen = now

	if v.tokens < 1 {
		return false
	}

	v.tokens--
	return true
}

// RateLimit returns a Gin middleware that rate-limits by client IP
func RateLimit(ratePerSec float64, burst int) gin.HandlerFunc {
	limiter := NewRateLimiter(ratePerSec, burst)

	return func(c *gin.Context) {
		ip := c.ClientIP()
		if !limiter.allow(ip) {
			c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{
				"success": false,
				"error":   "Rate limit exceeded. Please try again later.",
			})
			return
		}
		c.Next()
	}
}
