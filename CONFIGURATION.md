# Weather Alert Service - Configuration Management

## ✅ Configuration Management Principles

1. **Externalized Configuration**: All config via environment variables
2. **No Hardcoded Credentials**: Secrets from environment or AWS Secrets Manager
3. **12-Factor App Compliance**: Configuration separate from code
4. **Type Safety**: Strong typing with validation
5. **Sensible Defaults**: Works out-of-box for development

## 📋 Complete Configuration Reference

### Server Configuration

| Variable | Description | Default | Required | Example |
|----------|-------------|---------|----------|---------|
| `SERVER_PORT` | HTTP server port | `8080` | No | `8080` |
| `SERVER_READ_TIMEOUT` | Read timeout | `30s` | No | `30s` |
| `SERVER_WRITE_TIMEOUT` | Write timeout | `30s` | No | `30s` |
| `SERVER_IDLE_TIMEOUT` | Idle timeout | `120s` | No | `120s` |
| `SERVER_SHUTDOWN_TIMEOUT` | Graceful shutdown timeout | `30s` | No | `30s` |

### Weather API Configuration

| Variable | Description | Default | Required | Example |
|----------|-------------|---------|----------|---------|
| `OPENWEATHER_API_KEY` | OpenWeatherMap API key | - | **YES** | `abc123def456` |
| `OPENWEATHER_BASE_URL` | API base URL | `https://api.openweathermap.org/data/2.5` | No | Custom URL |
| `WEATHER_TIMEOUT` | API call timeout | `10s` | No | `5s` |
| `WEATHER_MAX_RETRIES` | Max retry attempts | `3` | No | `5` |
| `WEATHER_RETRY_DELAY` | Base retry delay | `1s` | No | `2s` |

### Cache Configuration

| Variable | Description | Default | Required | Example |
|----------|-------------|---------|----------|---------|
| `CACHE_TYPE` | Cache type (`memory` or `redis`) | `memory` | No | `redis` |
| `CACHE_TTL` | Cache time-to-live | `5m` | No | `10m` |
| `REDIS_ADDR` | Redis address | `localhost:6379` | If redis | `cache.example.com:6379` |
| `REDIS_PASSWORD` | Redis password | - | No | `secret123` |
| `REDIS_DB` | Redis database number | `0` | No | `1` |

### Rate Limiting Configuration

| Variable | Description | Default | Required | Example |
|----------|-------------|---------|----------|---------|
| `RATE_LIMIT_ENABLED` | Enable rate limiting | `true` | No | `false` |
| `RATE_LIMIT_RPS` | Requests per second | `100` | No | `200` |
| `RATE_LIMIT_BURST` | Burst capacity | `200` | No | `500` |

### Logging Configuration

| Variable | Description | Default | Required | Example |
|----------|-------------|---------|----------|---------|
| `LOG_LEVEL` | Log level (debug/info/warn/error) | `info` | No | `debug` |
| `LOG_FORMAT` | Log format (json/text) | `json` | No | `text` |
| `ENVIRONMENT` | Environment name | `development` | No | `production` |

### Application Metadata

| Variable | Description | Default | Required | Example |
|----------|-------------|---------|----------|---------|
| `VERSION` | Application version | `dev` | No | `1.0.0` |
| `SERVICE_NAME` | Service name | `weather-service` | No | Custom name |

## 🔧 Configuration Implementation

### Type-Safe Config Struct

**Location**: `internal/config/config.go`

```go
package config

import (
    "time"
    "github.com/kelseyhightower/envconfig"
)

type Config struct {
    Server    ServerConfig
    Weather   WeatherConfig
    Cache     CacheConfig
    RateLimit RateLimitConfig
    Logging   LoggingConfig
    Version   string `envconfig:"VERSION" default:"dev"`
}

type ServerConfig struct {
    Port            int           `envconfig:"SERVER_PORT" default:"8080"`
    ReadTimeout     time.Duration `envconfig:"SERVER_READ_TIMEOUT" default:"30s"`
    WriteTimeout    time.Duration `envconfig:"SERVER_WRITE_TIMEOUT" default:"30s"`
    IdleTimeout     time.Duration `envconfig:"SERVER_IDLE_TIMEOUT" default:"120s"`
    ShutdownTimeout time.Duration `envconfig:"SERVER_SHUTDOWN_TIMEOUT" default:"30s"`
}

type WeatherConfig struct {
    APIKey     string        `envconfig:"OPENWEATHER_API_KEY" required:"true"`
    BaseURL    string        `envconfig:"OPENWEATHER_BASE_URL" default:"https://api.openweathermap.org/data/2.5"`
    Timeout    time.Duration `envconfig:"WEATHER_TIMEOUT" default:"10s"`
    MaxRetries int           `envconfig:"WEATHER_MAX_RETRIES" default:"3"`
    RetryDelay time.Duration `envconfig:"WEATHER_RETRY_DELAY" default:"1s"`
}

type CacheConfig struct {
    Type     string        `envconfig:"CACHE_TYPE" default:"memory"`
    TTL      time.Duration `envconfig:"CACHE_TTL" default:"5m"`
    RedisAddr string       `envconfig:"REDIS_ADDR" default:"localhost:6379"`
    RedisPass string       `envconfig:"REDIS_PASSWORD"`
    RedisDB   int          `envconfig:"REDIS_DB" default:"0"`
}

type RateLimitConfig struct {
    Enabled          bool    `envconfig:"RATE_LIMIT_ENABLED" default:"true"`
    RequestsPerSecond float64 `envconfig:"RATE_LIMIT_RPS" default:"100"`
    Burst            int     `envconfig:"RATE_LIMIT_BURST" default:"200"`
}

type LoggingConfig struct {
    Level       string `envconfig:"LOG_LEVEL" default:"info"`
    Format      string `envconfig:"LOG_FORMAT" default:"json"`
    Environment string `envconfig:"ENVIRONMENT" default:"development"`
}

// Load loads configuration from environment variables
func Load() (*Config, error) {
    var cfg Config
    if err := envconfig.Process("", &cfg); err != nil {
        return nil, err
    }
    return &cfg, nil
}
```

### Configuration Loading

**Location**: `cmd/server/main.go`

```go
func main() {
    // Load configuration
    cfg, err := config.Load()
    if err != nil {
        log.Fatal().Err(err).Msg("Failed to load configuration")
    }
    
    // Validate required fields (envconfig handles this automatically)
    if cfg.Weather.APIKey == "" {
        log.Fatal().Msg("OPENWEATHER_API_KEY is required")
    }
    
    log.Info().
        Str("environment", cfg.Logging.Environment).
        Str("version", cfg.Version).
        Msg("Configuration loaded successfully")
}
```

## 🔐 Security: No Hardcoded Credentials

### ✅ Correct: Environment Variables

```go
// Config loaded from environment
cfg, err := config.Load()

// API key from environment
client := weather.NewClient(cfg.Weather.APIKey, ...)
```

### ❌ Incorrect: Hardcoded

```go
// NEVER DO THIS
apiKey := "abc123def456"  // Hardcoded - WRONG!
```

### Credential Sources

**Development**:
```bash
# .env file (gitignored)
export OPENWEATHER_API_KEY="your_dev_key_here"
export REDIS_PASSWORD="dev_password"
```

**Production (AWS ECS)**:
```json
{
  "secrets": [
    {
      "name": "OPENWEATHER_API_KEY",
      "valueFrom": "arn:aws:secretsmanager:us-east-2:123456:secret:weather-service/openweather-api-key"
    }
  ]
}
```

**Production (Kubernetes)**:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: weather-service-secrets
type: Opaque
data:
  OPENWEATHER_API_KEY: YWJjMTIzZGVmNDU2  # base64 encoded
---
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
      - name: weather-service
        envFrom:
        - secretRef:
            name: weather-service-secrets
```

## 📝 Example Configurations

### Development (Local)

**File**: `.env` (gitignored)

```bash
# Server
SERVER_PORT=8080

# Weather API
OPENWEATHER_API_KEY=your_dev_api_key_here

# Cache
CACHE_TYPE=memory
CACHE_TTL=5m

# Rate Limiting
RATE_LIMIT_ENABLED=true
RATE_LIMIT_RPS=100

# Logging
LOG_LEVEL=debug
LOG_FORMAT=text
ENVIRONMENT=development

# Version
VERSION=dev
```

### Development (Docker Compose)

**File**: `docker-compose.yml`

```yaml
version: '3.8'
services:
  weather-service:
    build: .
    environment:
      - OPENWEATHER_API_KEY=${OPENWEATHER_API_KEY}
      - CACHE_TYPE=redis
      - REDIS_ADDR=redis:6379
      - LOG_LEVEL=debug
      - ENVIRONMENT=docker
    env_file:
      - .env
```

### Production (AWS ECS)

**Terraform**: `deployments/terraform/ecs.tf`

```hcl
resource "aws_ecs_task_definition" "app" {
  container_definitions = jsonencode([{
    name  = "weather-service"
    image = "${var.ecr_repository_url}:${var.image_tag}"
    
    environment = [
      { name = "ENVIRONMENT", value = "production" },
      { name = "LOG_LEVEL", value = "info" },
      { name = "CACHE_TYPE", value = "redis" },
      { name = "REDIS_ADDR", value = "${aws_elasticache_cluster.redis.cache_nodes[0].address}:6379" },
      { name = "RATE_LIMIT_RPS", value = "200" }
    ]
    
    secrets = [
      {
        name      = "OPENWEATHER_API_KEY"
        valueFrom = data.aws_secretsmanager_secret.openweather_api_key.arn
      }
    ]
  }])
}
```

### Production (Kubernetes)

**File**: `deployments/kubernetes/deployment.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: weather-service-config
data:
  ENVIRONMENT: "production"
  LOG_LEVEL: "info"
  CACHE_TYPE: "redis"
  REDIS_ADDR: "redis-master:6379"
  RATE_LIMIT_RPS: "200"
---
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
      - name: weather-service
        envFrom:
        - configMapRef:
            name: weather-service-config
        - secretRef:
            name: weather-service-secrets
```

## ✅ Configuration Validation

### Startup Validation

```go
func (c *Config) Validate() error {
    // Required fields
    if c.Weather.APIKey == "" {
        return errors.New("OPENWEATHER_API_KEY is required")
    }
    
    // Validate enums
    if c.Cache.Type != "memory" && c.Cache.Type != "redis" {
        return fmt.Errorf("invalid CACHE_TYPE: %s (must be 'memory' or 'redis')", c.Cache.Type)
    }
    
    // Validate ranges
    if c.Server.Port < 1 || c.Server.Port > 65535 {
        return fmt.Errorf("invalid SERVER_PORT: %d", c.Server.Port)
    }
    
    // Redis validation
    if c.Cache.Type == "redis" && c.Cache.RedisAddr == "" {
        return errors.New("REDIS_ADDR is required when CACHE_TYPE=redis")
    }
    
    return nil
}
```

### Runtime Configuration Changes

**Not supported**: Configuration is loaded once at startup
**Reason**: Ensures consistency, prevents race conditions
**Alternative**: Rolling restart for config changes (zero-downtime via ECS/K8s)

## 🧪 Testing with Different Configs

### Unit Tests

```go
func TestConfigLoading(t *testing.T) {
    // Set test environment
    os.Setenv("OPENWEATHER_API_KEY", "test_key")
    os.Setenv("LOG_LEVEL", "debug")
    defer os.Clearenv()
    
    cfg, err := config.Load()
    assert.NoError(t, err)
    assert.Equal(t, "test_key", cfg.Weather.APIKey)
    assert.Equal(t, "debug", cfg.Logging.Level)
}
```

### Integration Tests

```bash
# Test with different cache types
CACHE_TYPE=memory go test ./...
CACHE_TYPE=redis REDIS_ADDR=localhost:6379 go test ./...

# Test with different log levels
LOG_LEVEL=debug go test ./...
```

## 📚 Configuration Documentation

### README.md

Contains:
- Quick start with minimal config
- Common configuration scenarios
- Environment-specific examples

### .env.example

Template file with all variables:

```bash
# Copy this file to .env and fill in your values
# cp .env.example .env

# Required
OPENWEATHER_API_KEY=your_api_key_here

# Optional (defaults shown)
SERVER_PORT=8080
CACHE_TYPE=memory
LOG_LEVEL=info
```

### DEPLOYMENT.md

Contains:
- Production configuration checklist
- AWS Secrets Manager setup
- Kubernetes secret creation
- Configuration best practices

## 🎯 Configuration Best Practices Applied

✅ **Externalized**: All config from environment
✅ **No secrets in code**: API keys from env/secrets manager
✅ **Type safe**: Strong typing with validation
✅ **Documented**: Every variable documented
✅ **Defaults**: Sensible defaults for development
✅ **Validation**: Startup validation with clear errors
✅ **12-Factor**: Strict separation of config and code
✅ **Environment-specific**: Different configs for dev/prod
✅ **Observable**: Config logged (without secrets) at startup

## 🔍 Debugging Configuration

### View Current Configuration

```bash
# Check what environment variables are set
env | grep -E "(SERVER_|WEATHER_|CACHE_|RATE_|LOG_|REDIS_)"

# View config at startup (from logs)
docker logs weather-service | grep "Configuration loaded"
```

### Common Issues

**Issue**: `OPENWEATHER_API_KEY is required`
**Solution**: Set the environment variable or add to .env file

**Issue**: Cache errors with `CACHE_TYPE=redis`
**Solution**: Check `REDIS_ADDR` and verify Redis is running

**Issue**: Rate limits too strict
**Solution**: Increase `RATE_LIMIT_RPS` and `RATE_LIMIT_BURST`

---

**All configuration is externalized, secure, validated, and fully documented.**
