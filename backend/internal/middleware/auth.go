package middleware

import (
	"net/http"
	"strings"

	"github.com/chizze/backend/internal/config"
	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

// AuthClaims holds the JWT claims
type AuthClaims struct {
	UserID string `json:"userId"`
	Role   string `json:"role"`
	jwt.RegisteredClaims
}

// ContextKey constants
const (
	ContextUserID = "userId"
	ContextRole   = "role"
)

// Auth middleware validates JWT token and injects user context
func Auth(cfg *config.Config) gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"success": false,
				"error":   "Missing Authorization header",
			})
			return
		}

		// Extract Bearer token
		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || strings.ToLower(parts[0]) != "bearer" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"success": false,
				"error":   "Invalid Authorization format. Use: Bearer <token>",
			})
			return
		}

		tokenStr := parts[1]

		// Parse and validate JWT
		claims := &AuthClaims{}
		token, err := jwt.ParseWithClaims(tokenStr, claims, func(t *jwt.Token) (interface{}, error) {
			return []byte(cfg.JWTSecret), nil
		})

		if err != nil || !token.Valid {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"success": false,
				"error":   "Invalid or expired token",
			})
			return
		}

		// Inject user context
		c.Set(ContextUserID, claims.UserID)
		c.Set(ContextRole, claims.Role)
		c.Next()
	}
}

// RequireRole middleware checks user has specific role
func RequireRole(roles ...string) gin.HandlerFunc {
	return func(c *gin.Context) {
		role, exists := c.Get(ContextRole)
		if !exists {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"success": false,
				"error":   "Role not set in context",
			})
			return
		}

		userRole := role.(string)
		for _, r := range roles {
			if r == userRole {
				c.Next()
				return
			}
		}

		c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
			"success": false,
			"error":   "Insufficient permissions",
		})
	}
}

// GetUserID extracts the user ID from gin context
func GetUserID(c *gin.Context) string {
	id, _ := c.Get(ContextUserID)
	if id == nil {
		return ""
	}
	return id.(string)
}

// GetUserRole extracts the user role from gin context
func GetUserRole(c *gin.Context) string {
	role, _ := c.Get(ContextRole)
	if role == nil {
		return ""
	}
	return role.(string)
}
