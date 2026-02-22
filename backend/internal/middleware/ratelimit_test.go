package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestRateLimiter_Allow(t *testing.T) {
	rl := &RateLimiter{
		rate:  10,
		burst: 5,
	}

	// First request should always be allowed (gets burst-1 tokens)
	allowed, remaining := rl.allow("192.168.1.1")
	if !allowed {
		t.Error("First request should be allowed")
	}
	if remaining != 4 { // burst(5) - 1
		t.Errorf("Remaining = %.0f, want 4", remaining)
	}
}

func TestRateLimiter_BurstExhaustion(t *testing.T) {
	rl := &RateLimiter{
		rate:  0.001, // Very slow refill
		burst: 3,
	}

	// First call sets tokens = burst - 1 = 2
	rl.allow("10.0.0.1")
	// Second call: tokens ≈ 2, consume one → 1
	allowed, _ := rl.allow("10.0.0.1")
	if !allowed {
		t.Error("Second request should be allowed")
	}
	// Third call: tokens ≈ 1, consume one → 0
	allowed, _ = rl.allow("10.0.0.1")
	if !allowed {
		t.Error("Third request should be allowed")
	}
	// Fourth call: tokens ≈ 0, should be denied
	allowed, _ = rl.allow("10.0.0.1")
	if allowed {
		t.Error("Fourth request should be denied (burst exhausted)")
	}
}

func TestRateLimiter_DifferentIPs(t *testing.T) {
	rl := &RateLimiter{
		rate:  0.001,
		burst: 1,
	}

	// First request from each IP should be allowed
	for _, ip := range []string{"1.1.1.1", "2.2.2.2", "3.3.3.3"} {
		allowed, _ := rl.allow(ip)
		if !allowed {
			t.Errorf("First request from %s should be allowed", ip)
		}
	}
}

func TestRateLimit_Middleware(t *testing.T) {
	r := gin.New()
	r.GET("/test", RateLimit(0.001, 2), func(c *gin.Context) {
		c.JSON(200, gin.H{"ok": true})
	})

	// First 2 requests should succeed (burst = 2)
	for i := 0; i < 2; i++ {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/test", nil)
		req.RemoteAddr = "192.168.1.1:1234"
		r.ServeHTTP(w, req)
		if w.Code != http.StatusOK {
			t.Errorf("Request %d: expected 200, got %d", i+1, w.Code)
		}
	}

	// Third request should be rate limited
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	req.RemoteAddr = "192.168.1.1:1234"
	r.ServeHTTP(w, req)
	if w.Code != http.StatusTooManyRequests {
		t.Errorf("Third request: expected 429, got %d", w.Code)
	}

	// Check rate limit headers
	if w.Header().Get("X-RateLimit-Limit") == "" {
		t.Error("Missing X-RateLimit-Limit header")
	}
	if w.Header().Get("Retry-After") == "" {
		t.Error("Missing Retry-After header on 429 response")
	}
}
