package redis

import (
	"errors"
	"testing"

	goredis "github.com/redis/go-redis/v9"
)

func TestIsNilError(t *testing.T) {
	if !IsNilError(goredis.Nil) {
		t.Error("IsNilError(redis.Nil) should be true")
	}
	if IsNilError(nil) {
		t.Error("IsNilError(nil) should be false")
	}
	if IsNilError(errors.New("other error")) {
		t.Error("IsNilError(other error) should be false")
	}
}

func TestClient_CloseNil(t *testing.T) {
	// Close on a client with nil rdb should not panic
	c := &Client{rdb: nil}
	err := c.Close()
	if err != nil {
		t.Errorf("Close on nil rdb should return nil, got %v", err)
	}
}

func TestClient_Underlying(t *testing.T) {
	// Create a client with a real go-redis instance (won't connect, just verifies method)
	rdb := goredis.NewClient(&goredis.Options{Addr: "localhost:6379"})
	defer rdb.Close()

	c := &Client{rdb: rdb}
	if c.Underlying() != rdb {
		t.Error("Underlying() should return the same redis client")
	}
	if c.GetRedis() != rdb {
		t.Error("GetRedis() should return the same redis client")
	}
}
