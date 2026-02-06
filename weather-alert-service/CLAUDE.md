# CLAUDE.md - AI Development Guidelines

This document provides guidance for Claude (or other AI assistants) when working on this codebase.

## 🎯 Project Context

This is a **production-ready Weather Alert Service** built as a take-home assessment for a Principal Site Reliability Engineer position. The emphasis is on:

1. **Observability** - Comprehensive metrics, logging, and alerting
2. **Reliability** - Retry logic, circuit breakers, graceful degradation
3. **Operational Excellence** - Easy to deploy, monitor, and debug
4. **Code Quality** - Clean, maintainable, well-tested code

## 📋 Architecture Overview

### Technology Stack
- **Language**: Go 1.21+
- **Framework**: Standard library with select libraries
- **Cache**: Redis (production) or in-memory (development)
- **Metrics**: Prometheus
- **Logging**: zerolog (structured JSON)
- **Deployment**: AWS ECS Fargate + Terraform
- **CI/CD**: GitHub Actions

### Key Design Patterns

1. **Middleware Chain Pattern** (`internal/api/handler.go`)
   - Recovery → Rate Limiting → Correlation ID → Metrics → Logging
   - Each middleware is composable and testable

2. **Retry with Exponential Backoff** (`internal/weather/client.go`)
   - Max 3 retries with exponential delay
   - Circuit breaker logic (documented)
   - Detailed retry metrics

3. **Cache Abstraction** (`internal/cache/cache.go`)
   - Interface-based design for easy swapping
   - Both Redis and in-memory implementations
   - Comprehensive cache metrics

4. **Configuration Management** (`internal/config/config.go`)
   - 12-factor app principles
   - All config via environment variables
   - Validation on startup

## 🔧 Common Development Tasks

### Adding a New Metric

1. Define the metric in `internal/metrics/metrics.go`:
```go
var newMetric = promauto.NewCounterVec(
    prometheus.CounterOpts{
        Name: "weather_new_metric_total",
        Help: "Description and USE CASE for this metric",
    },
    []string{"label1", "label2"},
)
```

2. Add a helper function:
```go
func RecordNewMetric(label1, label2 string) {
    newMetric.WithLabelValues(label1, label2).Inc()
}
```

3. Add corresponding alert in `deployments/prometheus/rules.yml`

4. Document in README.md under Observability section

### Adding a New Configuration Option

1. Add to config struct in `internal/config/config.go`:
```go
type Config struct {
    NewFeature NewFeatureConfig
}

type NewFeatureConfig struct {
    Enabled bool   `envconfig:"NEW_FEATURE_ENABLED" default:"false"`
    Timeout string `envconfig:"NEW_FEATURE_TIMEOUT" default:"10s"`
}
```

2. Add validation in `Validate()` method

3. Update README.md configuration table

4. Update Terraform if needed (`deployments/terraform/main.tf`)

### Adding a New API Endpoint

1. Add handler in `internal/api/handler.go`:
```go
func (h *Handler) NewEndpoint(w http.ResponseWriter, r *http.Request) {
    // Extract correlation ID
    correlationID := r.Context().Value("correlation_id")
    
    // Log request
    log.Info().
        Str("correlation_id", fmt.Sprintf("%v", correlationID)).
        Msg("Processing new endpoint")
    
    // Implement logic with proper error handling
    // ...
    
    respondJSON(w, http.StatusOK, data)
}
```

2. Register in `cmd/server/main.go`:
```go
mux.HandleFunc("/new-endpoint", handler.NewEndpoint)
```

3. Add tests in `internal/api/handler_test.go`

4. Update README.md API documentation

### Adding a New Alert

1. Add to `deployments/prometheus/rules.yml`:
```yaml
- alert: NewAlert
  expr: <promql_expression>
  for: 5m
  labels:
    severity: warning
    component: weather-service
  annotations:
    summary: "Brief description"
    description: "Detailed description with context"
    runbook_url: "https://github.com/matthew-goldman/sezzle/wiki/runbooks/new-alert"
```

2. Create runbook in `docs/runbooks/`

3. Test alert expression in Prometheus UI

## 🧪 Testing Guidelines

### Unit Tests
- Test files alongside source: `*_test.go`
- Use table-driven tests for multiple scenarios
- Mock external dependencies (weather API, cache)
- Aim for >80% coverage

Example:
```go
func TestFunction(t *testing.T) {
    tests := []struct {
        name    string
        input   string
        want    string
        wantErr bool
    }{
        {
            name:    "valid input",
            input:   "test",
            want:    "expected",
            wantErr: false,
        },
        // More cases...
    }
    
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got, err := Function(tt.input)
            if (err != nil) != tt.wantErr {
                t.Errorf("error = %v, wantErr %v", err, tt.wantErr)
                return
            }
            if got != tt.want {
                t.Errorf("got %v, want %v", got, tt.want)
            }
        })
    }
}
```

### Integration Tests
- Test against real Redis (docker-compose)
- Test API endpoints end-to-end
- Verify metrics are recorded correctly

## 📝 Code Style

### Logging
```go
// Always include correlation ID
log.Info().
    Str("correlation_id", fmt.Sprintf("%v", correlationID)).
    Str("key", "value").
    Msg("Event description")

// Use appropriate log levels
log.Debug() // Verbose debugging
log.Info()  // Important events
log.Warn()  // Recoverable errors
log.Error() // Errors requiring attention
log.Fatal() // Unrecoverable errors (use sparingly)
```

### Error Handling
```go
// Wrap errors with context
if err != nil {
    return fmt.Errorf("failed to do X: %w", err)
}

// Log before returning errors
log.Error().
    Err(err).
    Str("context", "value").
    Msg("Operation failed")
return err
```

### Metrics
```go
// Record at operation boundaries
start := time.Now()
result, err := DoOperation()
duration := time.Since(start).Seconds()

metrics.RecordOperation("success", duration)
```

## 🚀 Deployment Checklist

Before deploying changes:

1. ✅ All tests pass (`make test`)
2. ✅ Linter passes (`make lint`)
3. ✅ Documentation updated (README.md, CLAUDE.md)
4. ✅ Metrics added if new functionality
5. ✅ Alerts added if new failure modes
6. ✅ Terraform validated (`terraform validate`)
7. ✅ Docker image builds (`make docker-build`)
8. ✅ Changelog updated

## 🐛 Debugging Tips

### Local Development
```bash
# Run with debug logging
LOG_LEVEL=debug go run cmd/server/main.go

# Test specific endpoint
curl -v http://localhost:8080/weather/Boston

# View metrics
curl http://localhost:8080/metrics | grep weather_
```

### Production Issues

1. **Check logs** in CloudWatch:
```bash
aws logs tail /ecs/weather-service --follow
```

2. **Check metrics** in Prometheus/Grafana

3. **Check ECS service** health:
```bash
aws ecs describe-services --cluster weather-service-cluster --services weather-service
```

4. **Execute into container**:
```bash
aws ecs execute-command \
    --cluster weather-service-cluster \
    --task <task-id> \
    --container weather-service \
    --interactive \
    --command "/bin/sh"
```

## 📚 Key Files Reference

| File | Purpose |
|------|---------|
| `cmd/server/main.go` | Application entry point |
| `internal/api/handler.go` | HTTP handlers and middleware |
| `internal/metrics/metrics.go` | All Prometheus metrics |
| `internal/weather/client.go` | Weather API client with retries |
| `internal/cache/cache.go` | Cache abstraction |
| `deployments/terraform/main.tf` | AWS infrastructure |
| `deployments/prometheus/rules.yml` | Alert definitions |
| `.github/workflows/ci-cd.yml` | CI/CD pipeline |

## 🎓 Learning Resources

- [Prometheus Best Practices](https://prometheus.io/docs/practices/)
- [Go Testing Guide](https://go.dev/doc/tutorial/add-a-test)
- [Twelve-Factor App](https://12factor.net/)
- [SRE Book - Monitoring Distributed Systems](https://sre.google/sre-book/monitoring-distributed-systems/)
- [AWS ECS Best Practices](https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/)

## 💡 Design Decisions

### Why Go?
- Excellent standard library for HTTP servers
- Built-in concurrency (goroutines)
- Fast compilation and execution
- Great tooling (testing, profiling, formatting)
- Static binary deployment

### Why Prometheus?
- Industry standard for metrics
- Powerful query language (PromQL)
- Great for SLI/SLO tracking
- Excellent alerting capabilities

### Why ECS over EKS?
- Simpler for single-service deployments
- Lower operational overhead
- Faster to provision
- Good for this assessment scope

### Why Redis for caching?
- Production-ready persistence
- Low latency (~1ms)
- Built-in TTL support
- Easy to scale

## ⚠️ Common Pitfalls

1. **Don't log API keys** - Already filtered in logging middleware
2. **Don't forget correlation IDs** - Required for request tracing
3. **Don't skip error wrapping** - Context is crucial for debugging
4. **Don't create unbounded metrics** - Use appropriate cardinality
5. **Always test timeouts** - Context cancellation is critical
6. **Don't ignore health checks** - ECS/K8s rely on them

## 🤝 Contribution Workflow

1. Create feature branch from `develop`
2. Implement feature with tests
3. Update documentation
4. Run full test suite
5. Create PR with description
6. Address review comments
7. Merge to `develop` → Auto-deploy to dev
8. Merge to `main` → Auto-deploy to prod

## 📞 Getting Help

- Check README.md for general documentation
- Review existing code for patterns
- Check test files for examples
- Refer to Go documentation
- AWS documentation for infrastructure questions

---

**Remember**: This is a demonstration of SRE expertise. Every decision should show understanding of production operations, not just working code.
