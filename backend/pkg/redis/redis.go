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
