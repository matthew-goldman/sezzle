# Weather Alert Service

A production-ready weather alert service demonstrating SRE best practices including comprehensive observability, reliability patterns, and operational excellence.

## 🎯 Overview

This service provides weather information via RESTful API with enterprise-grade features:

- **OpenWeatherMap API integration** with retry logic and circuit breaker patterns
- **Comprehensive observability** with Prometheus metrics, structured logging, and distributed tracing
- **High availability** with caching (Redis/in-memory), rate limiting, and graceful degradation
- **Production deployment** on AWS ECS with Terraform IaC
- **CI/CD automation** via GitHub Actions
- **SLI/SLO monitoring** with alerting to PagerDuty/Slack

## ⚡ Quick Start

**Get running in 4 commands:**

```bash
# 1. Set your OpenWeatherMap API key:
export OPENWEATHER_API_KEY="your_key_here"

# 2. Set up all AWS resources (one command!)
make setup-aws

# 3. Deploy infrastructure
make terraform-apply

# 4. Build and push Docker image
make docker-push-aws
```

**Local development:**
```bash
make dev  # Starts service, Redis, Prometheus, Grafana
curl http://localhost:8080/weather/London
```

## 📋 Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [API Endpoints](#api-endpoints)
- [Configuration](#configuration)
- [Observability](#observability)
- [Deployment](#deployment)
- [Development](#development)
- [Testing](#testing)
- [Contributing](#contributing)

## ✨ Features

### Core Functionality
- 🌤️ Real-time weather data from OpenWeatherMap
- 🗺️ Location-based weather queries
- 💾 Intelligent caching (Redis or in-memory)
- 🔄 Automatic retry with exponential backoff
- 🚦 Request rate limiting
- 🎯 Correlation ID tracking

### Observability & Monitoring
- 📊 **Prometheus metrics**: request rates, latencies, error rates, cache hit rates, retry counts
- 📝 **Structured logging**: JSON logs with correlation IDs for request tracing
- 🔔 **Alerting**: Prometheus AlertManager with PagerDuty integration
- 📈 **SLI/SLO tracking**: Error budget monitoring and burn rate alerts
- 🔍 **Health checks**: Liveness and readiness probes

### Reliability Patterns
- 🔁 Retry logic with exponential backoff
- ⏱️ Context propagation and timeout management
- 🛡️ Rate limiting (token bucket algorithm)
- 🗄️ Multi-layer caching with TTL
- 🏥 Graceful shutdown
- 🔌 Circuit breaker (documented)

### Infrastructure & Deployment
- ☁️ AWS ECS Fargate deployment
- 🏗️ Infrastructure as Code (Terraform)
- 🚀 CI/CD with GitHub Actions
- 🐳 Multi-stage Docker builds
- ⚖️ Auto-scaling (CPU and memory based)
- 🌐 Application Load Balancer with health checks

## 🚀 Quick Start

### Prerequisites

- Go 1.21+
- Docker
- Terraform 1.4.4+
- AWS CLI (for cloud deployment)
- OpenWeatherMap API key ([get one free](https://openweathermap.org/api))

### Local Development

1. **Clone the repository**
```bash
git clone https://github.com/matthew-goldman/sezzle.git
cd sezzle
```

2. **Set environment variables**
```bash
export OPENWEATHER_API_KEY="your_api_key_here"
export CACHE_TYPE="memory"  # or "redis"
export LOG_LEVEL="debug"
```

3. **Run with Docker Compose**
```bash
make dev
```

OR run locally:

```bash
# Download dependencies
go mod download

# Run the service
make run
```

4. **Test the service**
```bash
# Health check
curl http://localhost:8080/health

# Get weather for a location
curl http://localhost:8080/weather/London

# View Prometheus metrics
curl http://localhost:8080/metrics
```

## 🔌 API Endpoints

### GET /weather/{location}

Retrieve current weather data for a specified location.

**Request:**
```bash
curl http://localhost:8080/weather/Seattle
```

**Response:**
```json
{
  "location": "Seattle",
  "temperature": 12.5,
  "conditions": "light rain",
  "humidity": 82,
  "wind_speed": 3.5,
  "timestamp": 1704470400
}
```

**Status Codes:**
- `200 OK`: Success
- `400 Bad Request`: Invalid location
- `429 Too Many Requests`: Rate limit exceeded
- `503 Service Unavailable`: Upstream API error

### GET /health

Service health check endpoint.

**Response:**
```json
{
  "status": "healthy",
  "timestamp": 1704470400,
  "version": "1.0.0"
}
```

### GET /metrics

Prometheus metrics endpoint.

**Response:** Prometheus text format metrics

## ⚙️ Configuration

All configuration via environment variables:

### Server Configuration
| Variable | Default | Description |
|----------|---------|-------------|
| `SERVER_PORT` | `8080` | HTTP server port |
| `SERVER_READ_TIMEOUT` | `10s` | Request read timeout |
| `SERVER_WRITE_TIMEOUT` | `10s` | Response write timeout |
| `SERVER_SHUTDOWN_TIMEOUT` | `30s` | Graceful shutdown timeout |

### Cache Configuration
| Variable | Default | Description |
|----------|---------|-------------|
| `CACHE_TYPE` | `memory` | Cache backend: `memory` or `redis` |
| `CACHE_TTL` | `5m` | Cache entry TTL |
| `REDIS_ADDR` | `localhost:6379` | Redis server address |
| `REDIS_PASSWORD` | `` | Redis password (optional) |

### Weather API Configuration
| Variable | Default | Description |
|----------|---------|-------------|
| `OPENWEATHER_API_KEY` | *required* | OpenWeatherMap API key |
| `OPENWEATHER_BASE_URL` | `https://api.openweathermap.org/data/2.5` | API base URL |
| `WEATHER_API_TIMEOUT` | `5s` | API request timeout |
| `WEATHER_MAX_RETRIES` | `3` | Max retry attempts |
| `WEATHER_RETRY_DELAY` | `1s` | Initial retry delay |

### Rate Limiting
| Variable | Default | Description |
|----------|---------|-------------|
| `RATE_LIMIT_ENABLED` | `true` | Enable rate limiting |
| `RATE_LIMIT_RPS` | `100` | Requests per second |
| `RATE_LIMIT_BURST` | `200` | Burst capacity |

### Logging
| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_LEVEL` | `info` | Log level: `debug`, `info`, `warn`, `error` |
| `ENVIRONMENT` | `development` | Environment name |

## 📊 Observability

### Prometheus Metrics

The service exposes comprehensive metrics at `/metrics`:

#### Request Metrics
- `weather_http_requests_total` - Total HTTP requests (by method, endpoint, status)
- `weather_http_request_duration_seconds` - Request latency histogram
- `weather_http_requests_in_flight` - Current active requests

#### Upstream API Metrics
- `weather_api_requests_total` - Total weather API requests (by status, location)
- `weather_api_request_duration_seconds` - API call latency
- `weather_api_retries_total` - Retry attempts (by location, reason)

#### Cache Metrics
- `weather_cache_hits_total` - Cache hits
- `weather_cache_misses_total` - Cache misses
- `weather_cache_errors_total` - Cache errors
- `weather_cache_size` - Current cache size

#### SLI Metrics
- `weather_request_success_total` - Request success/failure for SLO tracking
- `weather_rate_limit_exceeded_total` - Rate limit rejections

### Alerting Rules

See `deployments/prometheus/rules.yml` for comprehensive alerting:

- **SLO Burn Rate Alerts** - Track error budget consumption
- **Latency Alerts** - P99 latency thresholds
- **Upstream API Health** - Detect provider issues
- **Cache Performance** - Monitor hit rates and errors
- **Service Health** - Availability and resource usage

### Logging

Structured JSON logs with:
- Correlation IDs for request tracing
- Request/response metadata
- Error context with stack traces
- No sensitive data (API keys filtered)

Example log entry:
```json
{
  "level": "info",
  "correlation_id": "550e8400-e29b-41d4-a716-446655440000",
  "method": "GET",
  "path": "/weather/Boston",
  "status": 200,
  "duration": "245ms",
  "message": "Request completed"
}
```

## 🚀 Deployment

### AWS ECS (Recommended)

**Complete setup in 4 commands:**

1. **Set your API key**
```bash
export OPENWEATHER_API_KEY="your_api_key_here"
```

2. **Run complete AWS setup** (creates S3, DynamoDB, ECR, Secrets, IAM roles)
```bash
make setup-aws
```

This single command:
- ✅ Creates S3 bucket for Terraform state
- ✅ Creates DynamoDB table for state locking
- ✅ Creates ECR repository for Docker images
- ✅ Stores API key in Secrets Manager
- ✅ Creates all IAM roles (ECS + GitHub Actions)
- ✅ Generates `terraform.tfvars` automatically
- ✅ Runs `terraform init`

3. **Deploy infrastructure**
```bash
# Review the plan
make terraform-plan

# Apply
make terraform-apply
```

4. **Build and push Docker image**
```bash
make docker-push-aws
```

5. **Configure GitHub Actions** (for CI/CD)

Add this secret to your GitHub repository:
- Go to: https://github.com/matthew-goldman/sezzle/settings/secrets/actions
- Name: `AWS_ROLE_ARN`
- Value: (shown in setup-aws output)

6. **Deploy via CI/CD**
```bash
git push origin main
```

### Manual Setup (Alternative)

If you prefer step-by-step control, see `DEPLOYMENT.md` for detailed instructions.

### Kubernetes

```bash
# Create namespace and deploy
kubectl apply -f deployments/kubernetes/deployment.yaml

# Verify deployment
kubectl get pods -n weather-service
kubectl get svc -n weather-service

# View logs
kubectl logs -f -n weather-service deployment/weather-service
```

## 🛠️ Development

### Project Structure

```
.
├── cmd/
│   └── server/          # Application entry point
├── internal/
│   ├── api/             # HTTP handlers and middleware
│   ├── cache/           # Cache implementations
│   ├── config/          # Configuration management
│   ├── metrics/         # Prometheus metrics
│   └── weather/         # Weather API client
├── deployments/
│   ├── kubernetes/      # K8s manifests
│   ├── prometheus/      # Prometheus config
│   └── terraform/       # AWS infrastructure
├── docs/                # Additional documentation
├── scripts/             # Helper scripts
└── .github/workflows/   # CI/CD pipelines
```

### Makefile Commands

```bash
make help           # Show available commands
make build          # Build binary
make test           # Run tests
make lint           # Run linters
make docker-build   # Build Docker image
make dev            # Start development environment (docker-compose)
make docker-down    # Stop docker-compose

# AWS Deployment
make setup-aws      # Complete AWS setup (S3, IAM, ECR, Secrets)
make terraform-plan # Run Terraform plan
make terraform-apply # Apply Terraform changes
make docker-push-aws # Build and push to AWS ECR

# Kubernetes
make k8s-deploy     # Deploy to Kubernetes
make k8s-delete     # Delete from Kubernetes
make k8s-logs       # Show Kubernetes logs
```

## 🧪 Testing

```bash
# Run all tests
make test

# Run tests with coverage
go test -v -race -coverprofile=coverage.out ./...

# View coverage report
go tool cover -html=coverage.out

# Run specific tests
go test -v ./internal/cache/...

# Run with race detector
go test -race ./...
```

## 📈 SLI/SLO Definitions

### Service Level Objectives

| Metric | Target | Measurement Window |
|--------|--------|-------------------|
| **Availability** | 99.9% | 30 days |
| **Latency (P95)** | < 500ms | 5 minutes |
| **Latency (P99)** | < 1s | 5 minutes |
| **Error Rate** | < 0.1% | 5 minutes |

### Error Budget

- **Monthly budget**: 43.2 minutes of downtime
- **Burn rate alerts**: 
  - Critical: 10x burn rate (budget exhausted in 3 days)
  - Warning: 3x burn rate (budget exhausted in 10 days)

## 🔐 Security

- ✅ No hardcoded credentials
- ✅ API keys in AWS Secrets Manager
- ✅ Non-root container user
- ✅ Read-only root filesystem
- ✅ Security scanning in CI/CD
- ✅ TLS for external communication
- ✅ Rate limiting to prevent abuse

## 📚 Additional Documentation

- [Runbook: High Error Rate](docs/runbooks/high-error-rate.md)
- [Runbook: High Latency](docs/runbooks/high-latency.md)
- [Runbook: Upstream API Issues](docs/runbooks/upstream-api-issues.md)
- [Architecture Decision Records](docs/adr/)
- [SLO Dashboard](docs/slo-dashboard.md)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see LICENSE file for details.

## 👤 Author

**Matthew Goldman**

- GitHub: [@matthew-goldman](https://github.com/matthew-goldman)
- Project: [https://github.com/matthew-goldman/sezzle](https://github.com/matthew-goldman/sezzle)

## 🙏 Acknowledgments

- Built for Sezzle Principal SRE position
- OpenWeatherMap for weather data API
- Prometheus community for observability tools
