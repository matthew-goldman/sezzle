package cache

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"time"

	"github.com/matthew-goldman/sezzle/internal/metrics"
	"github.com/redis/go-redis/v9"
	"github.com/rs/zerolog/log"
)

// Cache defines the interface for cache operations
type Cache interface {
	Get(ctx context.Context, key string, dest interface{}) error
	Set(ctx context.Context, key string, value interface{}, ttl time.Duration) error
	Delete(ctx context.Context, key string) error
	Close() error
}

// MemoryCache implements an in-memory cache with TTL
type MemoryCache struct {
	data  map[string]*cacheEntry
	mu    sync.RWMutex
	ttl   time.Duration
	stopCh chan struct{}
}

type cacheEntry struct {
	value      []byte
	expiration time.Time
}

// NewMemoryCache creates a new in-memory cache
func NewMemoryCache(ttl time.Duration) *MemoryCache {
	mc := &MemoryCache{
		data:   make(map[string]*cacheEntry),
		ttl:    ttl,
		stopCh: make(chan struct{}),
	}

	// Start cleanup goroutine
	go mc.cleanup()

	return mc
}

// Get retrieves a value from the cache
func (mc *MemoryCache) Get(ctx context.Context, key string, dest interface{}) error {
	mc.mu.RLock()
	defer mc.mu.RUnlock()

	entry, exists := mc.data[key]
	if !exists || time.Now().After(entry.expiration) {
		metrics.RecordCacheMiss("memory")
		return fmt.Errorf("cache miss")
	}

	if err := json.Unmarshal(entry.value, dest); err != nil {
		metrics.RecordCacheError("memory", "unmarshal")
		return fmt.Errorf("failed to unmarshal cache value: %w", err)
	}

	metrics.RecordCacheHit("memory")
	return nil
}

// Set stores a value in the cache
func (mc *MemoryCache) Set(ctx context.Context, key string, value interface{}, ttl time.Duration) error {
	data, err := json.Marshal(value)
	if err != nil {
		metrics.RecordCacheError("memory", "marshal")
		return fmt.Errorf("failed to marshal cache value: %w", err)
	}

	if ttl == 0 {
		ttl = mc.ttl
	}

	mc.mu.Lock()
	defer mc.mu.Unlock()

	mc.data[key] = &cacheEntry{
		value:      data,
		expiration: time.Now().Add(ttl),
	}

	metrics.SetCacheSize(float64(len(mc.data)))
	return nil
}

// Delete removes a value from the cache
func (mc *MemoryCache) Delete(ctx context.Context, key string) error {
	mc.mu.Lock()
	defer mc.mu.Unlock()

	delete(mc.data, key)
	metrics.SetCacheSize(float64(len(mc.data)))
	return nil
}

// Close stops the cleanup goroutine
func (mc *MemoryCache) Close() error {
	close(mc.stopCh)
	return nil
}

// cleanup periodically removes expired entries
func (mc *MemoryCache) cleanup() {
	ticker := time.NewTicker(1 * time.Minute)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			mc.removeExpired()
		case <-mc.stopCh:
			return
		}
	}
}

func (mc *MemoryCache) removeExpired() {
	mc.mu.Lock()
	defer mc.mu.Unlock()

	now := time.Now()
	for key, entry := range mc.data {
		if now.After(entry.expiration) {
			delete(mc.data, key)
		}
	}

	metrics.SetCacheSize(float64(len(mc.data)))
}

// RedisCache implements a Redis-backed cache
type RedisCache struct {
	client *redis.Client
	ttl    time.Duration
}

// NewRedisCache creates a new Redis cache
func NewRedisCache(addr, password string, ttl time.Duration) (*RedisCache, error) {
	client := redis.NewClient(&redis.Options{
		Addr:     addr,
		Password: password,
		DB:       0,
	})

	// Test connection
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := client.Ping(ctx).Err(); err != nil {
		return nil, fmt.Errorf("failed to connect to Redis: %w", err)
	}

	log.Info().Str("addr", addr).Msg("Connected to Redis")

	return &RedisCache{
		client: client,
		ttl:    ttl,
	}, nil
}

// Get retrieves a value from Redis
func (rc *RedisCache) Get(ctx context.Context, key string, dest interface{}) error {
	val, err := rc.client.Get(ctx, key).Result()
	if err == redis.Nil {
		metrics.RecordCacheMiss("redis")
		return fmt.Errorf("cache miss")
	} else if err != nil {
		metrics.RecordCacheError("redis", "get")
		return fmt.Errorf("failed to get from Redis: %w", err)
	}

	if err := json.Unmarshal([]byte(val), dest); err != nil {
		metrics.RecordCacheError("redis", "unmarshal")
		return fmt.Errorf("failed to unmarshal cache value: %w", err)
	}

	metrics.RecordCacheHit("redis")
	return nil
}

// Set stores a value in Redis
func (rc *RedisCache) Set(ctx context.Context, key string, value interface{}, ttl time.Duration) error {
	data, err := json.Marshal(value)
	if err != nil {
		metrics.RecordCacheError("redis", "marshal")
		return fmt.Errorf("failed to marshal cache value: %w", err)
	}

	if ttl == 0 {
		ttl = rc.ttl
	}

	if err := rc.client.Set(ctx, key, data, ttl).Err(); err != nil {
		metrics.RecordCacheError("redis", "set")
		return fmt.Errorf("failed to set in Redis: %w", err)
	}

	return nil
}

// Delete removes a value from Redis
func (rc *RedisCache) Delete(ctx context.Context, key string) error {
	if err := rc.client.Del(ctx, key).Err(); err != nil {
		metrics.RecordCacheError("redis", "delete")
		return fmt.Errorf("failed to delete from Redis: %w", err)
	}

	return nil
}

// Close closes the Redis connection
func (rc *RedisCache) Close() error {
	return rc.client.Close()
}
