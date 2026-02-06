package config

import (
	"fmt"
	"time"

	"github.com/kelseyhightower/envconfig"
)

// Config holds all application configuration
type Config struct {
	Environment string `envconfig:"ENVIRONMENT" default:"development"`
	Version     string `envconfig:"VERSION" default:"dev"`
	LogLevel    string `envconfig:"LOG_LEVEL" default:"info"`

	Server    ServerConfig
	Cache     CacheConfig
	Weather   WeatherConfig
	RateLimit RateLimitConfig
}

// ServerConfig contains HTTP server settings
type ServerConfig struct {
	Port            int           `envconfig:"SERVER_PORT" default:"8080"`
	ReadTimeout     time.Duration `envconfig:"SERVER_READ_TIMEOUT" default:"10s"`
	WriteTimeout    time.Duration `envconfig:"SERVER_WRITE_TIMEOUT" default:"10s"`
	IdleTimeout     time.Duration `envconfig:"SERVER_IDLE_TIMEOUT" default:"60s"`
	ShutdownTimeout time.Duration `envconfig:"SERVER_SHUTDOWN_TIMEOUT" default:"30s"`
}

// CacheConfig contains cache settings
type CacheConfig struct {
	Type          string        `envconfig:"CACHE_TYPE" default:"memory"` // memory or redis
	TTL           time.Duration `envconfig:"CACHE_TTL" default:"5m"`
	RedisAddr     string        `envconfig:"REDIS_ADDR" default:"localhost:6379"`
	RedisPassword string        `envconfig:"REDIS_PASSWORD" default:""`
	RedisDB       int           `envconfig:"REDIS_DB" default:"0"`
}

// WeatherConfig contains weather API settings
type WeatherConfig struct {
	APIKey  string        `envconfig:"OPENWEATHER_API_KEY" required:"true"`
	BaseURL string        `envconfig:"OPENWEATHER_BASE_URL" default:"https://api.openweathermap.org/data/2.5"`
	Timeout time.Duration `envconfig:"WEATHER_API_TIMEOUT" default:"5s"`

	// Retry configuration
	MaxRetries    int           `envconfig:"WEATHER_MAX_RETRIES" default:"3"`
	RetryDelay    time.Duration `envconfig:"WEATHER_RETRY_DELAY" default:"1s"`
	RetryMaxDelay time.Duration `envconfig:"WEATHER_RETRY_MAX_DELAY" default:"10s"`
}

// RateLimitConfig contains rate limiting settings
type RateLimitConfig struct {
	Enabled           bool    `envconfig:"RATE_LIMIT_ENABLED" default:"true"`
	RequestsPerSecond float64 `envconfig:"RATE_LIMIT_RPS" default:"100"`
	Burst             int     `envconfig:"RATE_LIMIT_BURST" default:"200"`
}

// Load reads configuration from environment variables
func Load() (*Config, error) {
	var cfg Config

	if err := envconfig.Process("", &cfg); err != nil {
		return nil, fmt.Errorf("failed to process config: %w", err)
	}

	// Validate configuration
	if err := cfg.Validate(); err != nil {
		return nil, fmt.Errorf("invalid configuration: %w", err)
	}

	return &cfg, nil
}

// Validate checks configuration for correctness
func (c *Config) Validate() error {
	if c.Weather.APIKey == "" {
		return fmt.Errorf("OPENWEATHER_API_KEY is required")
	}

	if c.Cache.Type != "memory" && c.Cache.Type != "redis" {
		return fmt.Errorf("CACHE_TYPE must be 'memory' or 'redis'")
	}

	if c.Server.Port < 1 || c.Server.Port > 65535 {
		return fmt.Errorf("SERVER_PORT must be between 1 and 65535")
	}

	return nil
}
