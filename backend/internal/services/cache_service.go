package services

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"time"

	redispkg "github.com/chizze/backend/pkg/redis"
	goredis "github.com/redis/go-redis/v9"
)

// CacheService provides a typed caching layer backed by Redis
type CacheService struct {
	redis *redispkg.Client
}

// NewCacheService creates a new cache service
func NewCacheService(redisClient *redispkg.Client) *CacheService {
	return &CacheService{redis: redisClient}
}

// ─── Generic Get/Set ───

// GetJSON retrieves a cached JSON value and unmarshals it into dest.
// Returns false if the key doesn't exist.
func (cs *CacheService) GetJSON(ctx context.Context, key string, dest interface{}) (bool, error) {
	data, err := cs.redis.Get(ctx, key)
	if err == goredis.Nil {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("cache get %q: %w", key, err)
	}
	if err := json.Unmarshal([]byte(data), dest); err != nil {
		return false, fmt.Errorf("cache unmarshal %q: %w", key, err)
	}
	return true, nil
}

// SetJSON marshals value to JSON and stores it with the given TTL.
func (cs *CacheService) SetJSON(ctx context.Context, key string, value interface{}, ttl time.Duration) error {
	data, err := json.Marshal(value)
	if err != nil {
		return fmt.Errorf("cache marshal %q: %w", key, err)
	}
	return cs.redis.Set(ctx, key, data, ttl)
}

// Invalidate removes one or more cache keys.
func (cs *CacheService) Invalidate(ctx context.Context, keys ...string) {
	if err := cs.redis.Del(ctx, keys...); err != nil {
		log.Printf("WARN: cache invalidate failed: %v", err)
	}
}

// ─── Domain-Specific Cache Keys ───

const (
	// TTLs
	RestaurantListTTL  = 2 * time.Minute
	RestaurantDetailTTL = 5 * time.Minute
	MenuTTL            = 3 * time.Minute
	UserProfileTTL     = 5 * time.Minute
	CouponListTTL      = 10 * time.Minute
)

// RestaurantListKey returns the cache key for restaurant listings
func RestaurantListKey(page, limit int) string {
	return fmt.Sprintf("restaurants:list:%d:%d", page, limit)
}

// RestaurantDetailKey returns the cache key for a single restaurant
func RestaurantDetailKey(id string) string {
	return fmt.Sprintf("restaurants:detail:%s", id)
}

// RestaurantMenuKey returns the cache key for a restaurant's menu
func RestaurantMenuKey(restaurantID string) string {
	return fmt.Sprintf("restaurants:menu:%s", restaurantID)
}

// UserProfileKey returns the cache key for a user profile
func UserProfileKey(userID string) string {
	return fmt.Sprintf("users:profile:%s", userID)
}

// CouponListKey returns the cache key for available coupons
func CouponListKey() string {
	return "coupons:available"
}
