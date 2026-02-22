package middleware

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/chizze/backend/internal/config"
	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

func init() {
	gin.SetMode(gin.TestMode)
}

func createTestToken(secret, userID, role string, expiry time.Duration) string {
	claims := AuthClaims{
		UserID: userID,
		Role:   role,
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    "chizze-api",
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(expiry)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenStr, _ := token.SignedString([]byte(secret))
	return tokenStr
}

func TestAuth_MissingHeader(t *testing.T) {
	cfg := &config.Config{JWTSecret: "test-secret"}
	r := gin.New()
	r.GET("/test", Auth(cfg), func(c *gin.Context) {
		c.JSON(200, gin.H{"ok": true})
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401, got %d", w.Code)
	}
}

func TestAuth_InvalidFormat(t *testing.T) {
	cfg := &config.Config{JWTSecret: "test-secret"}
	r := gin.New()
	r.GET("/test", Auth(cfg), func(c *gin.Context) {
		c.JSON(200, gin.H{"ok": true})
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	req.Header.Set("Authorization", "InvalidFormat")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401, got %d", w.Code)
	}
}

func TestAuth_InvalidToken(t *testing.T) {
	cfg := &config.Config{JWTSecret: "test-secret"}
	r := gin.New()
	r.GET("/test", Auth(cfg), func(c *gin.Context) {
		c.JSON(200, gin.H{"ok": true})
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	req.Header.Set("Authorization", "Bearer invalid.token.here")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401, got %d", w.Code)
	}
}

func TestAuth_ExpiredToken(t *testing.T) {
	cfg := &config.Config{JWTSecret: "test-secret"}
	token := createTestToken("test-secret", "user1", "customer", -1*time.Hour) // expired

	r := gin.New()
	r.GET("/test", Auth(cfg), func(c *gin.Context) {
		c.JSON(200, gin.H{"ok": true})
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401, got %d", w.Code)
	}
}

func TestAuth_WrongSecret(t *testing.T) {
	cfg := &config.Config{JWTSecret: "correct-secret"}
	token := createTestToken("wrong-secret", "user1", "customer", 1*time.Hour)

	r := gin.New()
	r.GET("/test", Auth(cfg), func(c *gin.Context) {
		c.JSON(200, gin.H{"ok": true})
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401, got %d", w.Code)
	}
}

func TestAuth_ValidToken(t *testing.T) {
	cfg := &config.Config{JWTSecret: "test-secret"}
	token := createTestToken("test-secret", "user_123", "customer", 1*time.Hour)

	var capturedUserID, capturedRole string

	r := gin.New()
	r.GET("/test", Auth(cfg), func(c *gin.Context) {
		capturedUserID = GetUserID(c)
		capturedRole = GetUserRole(c)
		c.JSON(200, gin.H{"ok": true})
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected 200, got %d", w.Code)
	}
	if capturedUserID != "user_123" {
		t.Errorf("UserID = %q, want 'user_123'", capturedUserID)
	}
	if capturedRole != "customer" {
		t.Errorf("Role = %q, want 'customer'", capturedRole)
	}
}

func TestRequireRole_Allowed(t *testing.T) {
	r := gin.New()
	r.GET("/test", func(c *gin.Context) {
		c.Set(ContextRole, "admin")
		c.Next()
	}, RequireRole("admin", "customer"), func(c *gin.Context) {
		c.JSON(200, gin.H{"ok": true})
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected 200, got %d", w.Code)
	}
}

func TestRequireRole_Forbidden(t *testing.T) {
	r := gin.New()
	r.GET("/test", func(c *gin.Context) {
		c.Set(ContextRole, "customer")
		c.Next()
	}, RequireRole("admin"), func(c *gin.Context) {
		c.JSON(200, gin.H{"ok": true})
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusForbidden {
		t.Errorf("Expected 403, got %d", w.Code)
	}
}

func TestRequireRole_NoRoleSet(t *testing.T) {
	r := gin.New()
	r.GET("/test", RequireRole("admin"), func(c *gin.Context) {
		c.JSON(200, gin.H{"ok": true})
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusForbidden {
		t.Errorf("Expected 403, got %d", w.Code)
	}
}

func TestGetUserID_NoContext(t *testing.T) {
	r := gin.New()
	r.GET("/test", func(c *gin.Context) {
		id := GetUserID(c)
		c.JSON(200, gin.H{"id": id})
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	r.ServeHTTP(w, req)

	var body map[string]string
	json.Unmarshal(w.Body.Bytes(), &body)
	if body["id"] != "" {
		t.Errorf("Expected empty string, got %q", body["id"])
	}
}

func TestGetUserRole_NoContext(t *testing.T) {
	r := gin.New()
	r.GET("/test", func(c *gin.Context) {
		role := GetUserRole(c)
		c.JSON(200, gin.H{"role": role})
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	r.ServeHTTP(w, req)

	var body map[string]string
	json.Unmarshal(w.Body.Bytes(), &body)
	if body["role"] != "" {
		t.Errorf("Expected empty string, got %q", body["role"])
	}
}
