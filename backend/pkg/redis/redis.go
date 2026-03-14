package redis

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/redis/go-redis/v9"
)

// Client wraps the go-redis client with convenience methods
type Client struct {
	rdb *redis.Client
}

// NewClient creates and validates a Redis connection.
// It accepts a Redis URL like "redis://:password@host:port" or
// individual host/password/db components via options.
func NewClient(redisURL string) (*Client, error) {
	opts, err := redis.ParseURL(redisURL)
	if err != nil {
		return nil, fmt.Errorf("invalid REDIS_URL: %w", err)
	}

	// Connection pool tuning
	opts.PoolSize = 20
	opts.MinIdleConns = 5
	opts.DialTimeout = 5 * time.Second
	opts.ReadTimeout = 3 * time.Second
	opts.WriteTimeout = 3 * time.Second
	opts.PoolTimeout = 4 * time.Second

	rdb := redis.NewClient(opts)

	// Verify connectivity
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := rdb.Ping(ctx).Err(); err != nil {
		rdb.Close()
		return nil, fmt.Errorf("redis ping failed: %w", err)
	}

	log.Printf("✅ Redis connected: %s", opts.Addr)
	return &Client{rdb: rdb}, nil
}

// Close gracefully shuts down the Redis connection pool
func (c *Client) Close() error {
	if c.rdb != nil {
		return c.rdb.Close()
	}
	return nil
}

// Ping checks Redis connectivity (for health checks)
func (c *Client) Ping(ctx context.Context) error {
	return c.rdb.Ping(ctx).Err()
}

// Underlying returns the raw go-redis client for advanced usage
func (c *Client) Underlying() *redis.Client {
	return c.rdb
}

// GetRedis returns the raw go-redis client (alias for Underlying)
func (c *Client) GetRedis() *redis.Client {
	return c.rdb
}

// ─── Key-Value Helpers ───

// Get retrieves a value by key. Returns empty string and redis.Nil if not found.
func (c *Client) Get(ctx context.Context, key string) (string, error) {
	return c.rdb.Get(ctx, key).Result()
}

// Set stores a key-value pair with an expiration.
func (c *Client) Set(ctx context.Context, key string, value interface{}, expiration time.Duration) error {
	return c.rdb.Set(ctx, key, value, expiration).Err()
}

// Del removes one or more keys.
func (c *Client) Del(ctx context.Context, keys ...string) error {
	return c.rdb.Del(ctx, keys...).Err()
}

// Exists checks whether a key exists.
func (c *Client) Exists(ctx context.Context, key string) (bool, error) {
	n, err := c.rdb.Exists(ctx, key).Result()
	return n > 0, err
}

// Incr atomically increments a key and returns the new value.
func (c *Client) Incr(ctx context.Context, key string) (int64, error) {
	return c.rdb.Incr(ctx, key).Result()
}

// Decr atomically decrements a key and returns the new value.
func (c *Client) Decr(ctx context.Context, key string) (int64, error) {
	return c.rdb.Decr(ctx, key).Result()
}

// SetNX sets a key only if it does not exist (distributed lock primitive).
// Returns true if the key was set, false if it already existed.
func (c *Client) SetNX(ctx context.Context, key string, value interface{}, expiration time.Duration) (bool, error) {
	return c.rdb.SetNX(ctx, key, value, expiration).Result()
}

// Expire sets a TTL on a key.
func (c *Client) Expire(ctx context.Context, key string, ttl time.Duration) error {
	return c.rdb.Expire(ctx, key, ttl).Err()
}

// TTL returns the remaining time-to-live of a key.
func (c *Client) TTL(ctx context.Context, key string) (time.Duration, error) {
	return c.rdb.TTL(ctx, key).Result()
}

// ─── Rate Limiting (Sliding Window) ───

// RateLimitCheck uses a sliding-window counter in Redis.
// Returns (allowed bool, remaining int64, retryAfter time.Duration).
func (c *Client) RateLimitCheck(ctx context.Context, key string, limit int64, window time.Duration) (bool, int64, time.Duration) {
	pipe := c.rdb.Pipeline()

	incr := pipe.Incr(ctx, key)
	pipe.Expire(ctx, key, window)
	ttl := pipe.TTL(ctx, key)

	_, err := pipe.Exec(ctx)
	if err != nil {
		// On Redis error, allow the request (fail-open)
		log.Printf("WARN: Redis rate limit error: %v — allowing request", err)
		return true, limit, 0
	}

	count := incr.Val()
	remaining := limit - count
	if remaining < 0 {
		remaining = 0
	}

	if count > limit {
		retryAfter := ttl.Val()
		if retryAfter < 0 {
			retryAfter = window
		}
		return false, 0, retryAfter
	}

	return true, remaining, 0
}

// ─── Geo Helpers (for rider location matching) ───

// GeoAdd adds a member with longitude/latitude to a geo set.
func (c *Client) GeoAdd(ctx context.Context, key string, members ...*redis.GeoLocation) (int64, error) {
	return c.rdb.GeoAdd(ctx, key, members...).Result()
}

// GeoSearch searches for members within a sorted set that match geo criteria.
// Returns a list of member names (strings).
// Falls back to GEORADIUS when GEOSEARCH is not available (e.g. older Redis / miniredis).
func (c *Client) GeoSearch(ctx context.Context, key string, q *redis.GeoSearchQuery) ([]string, error) {
	results, err := c.rdb.GeoSearch(ctx, key, q).Result()
	if err == nil {
		return results, nil
	}

	// Fallback to GEORADIUS for environments that don't support GEOSEARCH
	if q.Radius > 0 && q.RadiusUnit != "" {
		unit := q.RadiusUnit
		count := q.Count
		if count == 0 {
			count = 50
		}
		geoQuery := &redis.GeoRadiusQuery{
			Radius:   q.Radius,
			Unit:     unit,
			Sort:     q.Sort,
			Count:    int(count),
		}
		locs, err2 := c.rdb.GeoRadius(ctx, key, q.Longitude, q.Latitude, geoQuery).Result()
		if err2 != nil {
			return nil, err // return original error if fallback also fails
		}
		names := make([]string, len(locs))
		for i, loc := range locs {
			names[i] = loc.Name
		}
		return names, nil
	}

	return results, err
}

// GeoPos returns the longitude and latitude for one or more members of a geo set.
// Returns nil entries for members that don't exist.
func (c *Client) GeoPos(ctx context.Context, key string, members ...string) ([]*redis.GeoPos, error) {
	return c.rdb.GeoPos(ctx, key, members...).Result()
}

// ZRem removes one or more members from a sorted set (used to remove riders from geo set).
func (c *Client) ZRem(ctx context.Context, key string, members ...interface{}) (int64, error) {
	return c.rdb.ZRem(ctx, key, members...).Result()
}

// ─── Set Helpers ───

// SAdd adds one or more members to a set.
func (c *Client) SAdd(ctx context.Context, key string, members ...interface{}) (int64, error) {
	return c.rdb.SAdd(ctx, key, members...).Result()
}

// SMembers returns all members in a set.
func (c *Client) SMembers(ctx context.Context, key string) ([]string, error) {
	return c.rdb.SMembers(ctx, key).Result()
}

// ─── List Helpers (for notification queue) ───

// LPush prepends one or more values to a list.
func (c *Client) LPush(ctx context.Context, key string, values ...interface{}) (int64, error) {
	return c.rdb.LPush(ctx, key, values...).Result()
}

// BRPop is a blocking pop from one or more lists with a timeout.
// Returns the key and value that was popped.
func (c *Client) BRPop(ctx context.Context, timeout time.Duration, keys ...string) ([]string, error) {
	return c.rdb.BRPop(ctx, timeout, keys...).Result()
}

// ─── Error Helpers ───

// IsNilError returns true if the given error is redis.Nil (key not found).
func IsNilError(err error) bool {
	return err == redis.Nil
}
