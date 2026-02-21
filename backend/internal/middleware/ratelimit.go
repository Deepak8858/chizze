package middleware

import (
	"fmt"
	"net/http"
	"strconv"
	"sync"
	"time"

	redispkg "github.com/chizze/backend/pkg/redis"
	"github.com/gin-gonic/gin"
)

// visitor tracks request timestamps per IP
type visitor struct {
	lastSeen time.Time
	tokens   float64
}

// RateLimiter implements a token-bucket rate limiter
type RateLimiter struct {
	visitors sync.Map // lock-free concurrent map
	rate     float64  // tokens per second
	burst    float64  // max tokens
}

// NewRateLimiter creates a rate limiter
func NewRateLimiter(ratePerSec float64, burst int) *RateLimiter {
	rl := &RateLimiter{
		rate:  ratePerSec,
		burst: float64(burst),
	}

	// Cleanup stale visitors every 2 minutes
	go func() {
		for {
			time.Sleep(2 * time.Minute)
			rl.cleanup()
		}
	}()

	return rl
}

func (rl *RateLimiter) cleanup() {
	now := time.Now()
	rl.visitors.Range(func(key, value interface{}) bool {
		v := value.(*visitor)
		if now.Sub(v.lastSeen) > 5*time.Minute {
			rl.visitors.Delete(key)
		}
		return true
	})
}

func (rl *RateLimiter) allow(ip string) (bool, float64) {
	now := time.Now()

	val, loaded := rl.visitors.Load(ip)
	if !loaded {
		v := &visitor{lastSeen: now, tokens: rl.burst - 1}
		rl.visitors.Store(ip, v)
		return true, rl.burst - 1
	}

	v := val.(*visitor)

	// Refill tokens based on elapsed time
	elapsed := now.Sub(v.lastSeen).Seconds()
	v.tokens += elapsed * rl.rate
	if v.tokens > rl.burst {
		v.tokens = rl.burst
	}
	v.lastSeen = now

	if v.tokens < 1 {
		return false, 0
	}

	v.tokens--
	return true, v.tokens
}

// RateLimit returns a Gin middleware that rate-limits by client IP
// Includes X-RateLimit-* headers for client awareness
func RateLimit(ratePerSec float64, burst int) gin.HandlerFunc {
	limiter := NewRateLimiter(ratePerSec, burst)

	return func(c *gin.Context) {
		ip := c.ClientIP()
		allowed, remaining := limiter.allow(ip)

		// Set rate limit headers
		c.Header("X-RateLimit-Limit", strconv.Itoa(burst))
		c.Header("X-RateLimit-Remaining", strconv.FormatFloat(remaining, 'f', 0, 64))

		if !allowed {
			c.Header("Retry-After", "1")
			c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{
				"success": false,
				"error":   "Rate limit exceeded. Please try again later.",
			})
			return
		}
		c.Next()
	}
}

// RedisRateLimit returns a Gin middleware that uses Redis for distributed
// rate limiting via a sliding-window counter. Falls back to allow on Redis errors.
func RedisRateLimit(redisClient *redispkg.Client, ratePerSec float64, burst int) gin.HandlerFunc {
	window := time.Second
	limit := int64(burst)

	return func(c *gin.Context) {
		ip := c.ClientIP()
		key := fmt.Sprintf("rl:%s", ip)

		allowed, remaining, retryAfter := redisClient.RateLimitCheck(c.Request.Context(), key, limit, window)

		// Set rate limit headers
		c.Header("X-RateLimit-Limit", strconv.Itoa(burst))
		c.Header("X-RateLimit-Remaining", strconv.FormatInt(remaining, 10))

		if !allowed {
			retrySeconds := int(retryAfter.Seconds())
			if retrySeconds < 1 {
				retrySeconds = 1
			}
			c.Header("Retry-After", strconv.Itoa(retrySeconds))
			c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{
				"success": false,
				"error":   "Rate limit exceeded. Please try again later.",
			})
			return
		}
		c.Next()
	}
}
