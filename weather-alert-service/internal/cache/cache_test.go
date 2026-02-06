package cache

import (
	"context"
	"testing"
	"time"
)

func TestMemoryCache_SetAndGet(t *testing.T) {
	cache := NewMemoryCache(5 * time.Minute)
	defer cache.Close()

	ctx := context.Background()

	// Test Set and Get
	type testData struct {
		Value string `json:"value"`
	}

	original := testData{Value: "test"}
	err := cache.Set(ctx, "test-key", original, 0)
	if err != nil {
		t.Fatalf("Set failed: %v", err)
	}

	var retrieved testData
	err = cache.Get(ctx, "test-key", &retrieved)
	if err != nil {
		t.Fatalf("Get failed: %v", err)
	}

	if retrieved.Value != original.Value {
		t.Errorf("Expected %s, got %s", original.Value, retrieved.Value)
	}
}

func TestMemoryCache_Miss(t *testing.T) {
	cache := NewMemoryCache(5 * time.Minute)
	defer cache.Close()

	ctx := context.Background()

	var data string
	err := cache.Get(ctx, "nonexistent", &data)
	if err == nil {
		t.Error("Expected error for cache miss, got nil")
	}
}

func TestMemoryCache_Expiration(t *testing.T) {
	cache := NewMemoryCache(1 * time.Second)
	defer cache.Close()

	ctx := context.Background()

	err := cache.Set(ctx, "expiring-key", "value", 100*time.Millisecond)
	if err != nil {
		t.Fatalf("Set failed: %v", err)
	}

	// Should exist immediately
	var data string
	err = cache.Get(ctx, "expiring-key", &data)
	if err != nil {
		t.Fatalf("Get failed immediately after set: %v", err)
	}

	// Wait for expiration
	time.Sleep(150 * time.Millisecond)

	err = cache.Get(ctx, "expiring-key", &data)
	if err == nil {
		t.Error("Expected error for expired key, got nil")
	}
}

func TestMemoryCache_Delete(t *testing.T) {
	cache := NewMemoryCache(5 * time.Minute)
	defer cache.Close()

	ctx := context.Background()

	err := cache.Set(ctx, "delete-key", "value", 0)
	if err != nil {
		t.Fatalf("Set failed: %v", err)
	}

	err = cache.Delete(ctx, "delete-key")
	if err != nil {
		t.Fatalf("Delete failed: %v", err)
	}

	var data string
	err = cache.Get(ctx, "delete-key", &data)
	if err == nil {
		t.Error("Expected error for deleted key, got nil")
	}
}
