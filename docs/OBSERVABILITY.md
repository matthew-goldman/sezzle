# Weather Alert Service - Observability Strategy

## Overview

This document explains our comprehensive observability implementation following the **Three Pillars of Observability**: Metrics, Logs, and Traces.

## 📊 Metrics (Prometheus)

We implement **15+ metrics** covering the **USE Method** (Utilization, Saturation, Errors) and **RED Method** (Rate, Errors, Duration):

### HTTP Layer Metrics (RED Method)

#### 1. `weather_http_requests_total` (Counter)
**Purpose**: Track request volume by method, endpoint, and status code
**Use Case**: 
- Identify traffic patterns and peak load times
- Calculate error rates and success rates
- Detect anomalous traffic spikes
**Alert Conditions**:
- Sudden drops (>50% in 5m) → Service unavailable
- High 5xx rate (>1% in 5m) → Application errors
- High 4xx rate (>10% in 5m) → Client errors or API misuse

**Example Query**:
```promql
rate(weather_http_requests_total[5m])  # Request rate
rate(weather_http_requests_total{status=~"5.."}[5m]) / rate(weather_http_requests_total[5m])  # Error rate
```

#### 2. `weather_http_request_duration_seconds` (Histogram)
**Purpose**: Track request latency distribution
**Use Case**:
- Monitor API response times (P50, P95, P99)
- Identify performance degradation
- Set SLO targets (e.g., P95 < 500ms)
**Alert Conditions**:
- P95 > 500ms for 5m → Warning
- P99 > 1s for 5m → Critical
- P99 > 5s for 2m → Page SRE

**Example Query**:
```promql
histogram_quantile(0.95, rate(weather_http_request_duration_seconds_bucket[5m]))  # P95 latency
histogram_quantile(0.99, rate(weather_http_request_duration_seconds_bucket[5m]))  # P99 latency
```

#### 3. `weather_http_requests_in_flight` (Gauge)
**Purpose**: Track concurrent active requests
**Use Case**:
- Monitor saturation (USE method)
- Identify slow endpoints causing request queuing
- Capacity planning for horizontal scaling
**Alert Conditions**:
- Sustained high (>100) for 10m → Scale out needed
- Spike with high latency → Slow downstream dependency

**Example Query**:
```promql
weather_http_requests_in_flight > 100  # Saturation alert
```

### Upstream API Metrics

#### 4. `weather_api_requests_total` (Counter)
**Purpose**: Track calls to OpenWeatherMap API
**Use Case**:
- Monitor API quota usage
- Detect upstream integration issues
- Optimize cache to reduce API calls
**Alert Conditions**:
- High error rate (>10% in 5m) → Upstream degradation
- Error rate >90% for 2m → Upstream outage, page immediately

**Example Query**:
```promql
rate(weather_api_requests_total{status="error"}[5m]) / rate(weather_api_requests_total[5m]) > 0.1
```

#### 5. `weather_api_request_duration_seconds` (Histogram)
**Purpose**: Track upstream API latency
**Use Case**:
- Monitor third-party dependency performance
- Adjust cache TTL based on API speed
- Trigger circuit breaker if needed
**Alert Conditions**:
- P95 > 2s for 5m → Upstream slow
- P95 > 5s for 2m → Consider circuit breaker

#### 6. `weather_api_retries_total` (Counter)
**Purpose**: Track retry attempts by location and reason
**Use Case**:
- Monitor reliability of upstream API
- Identify which locations/endpoints are problematic
- Validate retry logic effectiveness
**Alert Conditions**:
- Retry rate >5/sec for 5m → Upstream instability
- High retries for specific location → Investigate API regional issues

**Example Query**:
```promql
rate(weather_api_retries_total[5m]) > 5  # High retry rate
sum by (reason) (rate(weather_api_retries_total[5m]))  # Group by failure reason
```

### Cache Metrics (Performance & Reliability)

#### 7. `weather_cache_hits_total` (Counter)
#### 8. `weather_cache_misses_total` (Counter)
**Purpose**: Measure cache effectiveness
**Use Case**:
- Calculate cache hit ratio
- Optimize cache TTL and eviction policy
- Reduce API costs by maximizing cache hits
**Alert Conditions**:
- Hit rate <50% for 10m → Cache not effective, investigate TTL
- Sudden drop in hits → Cache failure or eviction issues

**Example Query**:
```promql
# Cache hit ratio
rate(weather_cache_hits_total[5m]) / 
(rate(weather_cache_hits_total[5m]) + rate(weather_cache_misses_total[5m]))
```

#### 9. `weather_cache_errors_total` (Counter)
**Purpose**: Track cache operation failures
**Use Case**:
- Monitor Redis health
- Detect connection issues or memory problems
- Validate graceful degradation (service continues without cache)
**Alert Conditions**:
- ANY cache errors → Critical alert (Redis down or misconfigured)

#### 10. `weather_cache_size` (Gauge)
**Purpose**: Track number of cached items
**Use Case**:
- Monitor memory usage growth
- Detect cache key issues or leaks
- Capacity planning for Redis
**Alert Conditions**:
- Unexpected rapid growth → Cache key problem
- Size approaching limit → Scale Redis

### Rate Limiting & Protection

#### 11. `weather_rate_limit_exceeded_total` (Counter)
**Purpose**: Track rejected requests by endpoint
**Use Case**:
- Monitor rate limit effectiveness
- Detect abuse or DDoS attempts
- Adjust rate limits based on traffic patterns
**Alert Conditions**:
- High rejection rate (>10/sec) → Possible attack or limit too strict
- All requests rejected → Misconfigured rate limit

### Circuit Breaker

#### 12. `weather_circuit_breaker_state` (Gauge)
**Purpose**: Monitor circuit breaker status (0=closed, 1=open, 2=half-open)
**Use Case**:
- Track when upstream failures trigger circuit breaker
- Monitor automatic recovery attempts
- Prevent cascading failures
**Alert Conditions**:
- State = 1 (open) → Upstream service failed, immediate attention
- Flapping (open/closed cycles) → Intermittent upstream issues

### SLI/SLO Metrics

#### 13. `weather_request_success_total` (Counter)
**Purpose**: Track successful vs failed requests for SLO calculation
**Use Case**:
- Calculate availability SLI (e.g., 99.9% target)
- Monitor error budget consumption
- Multi-window, multi-burn-rate alerting
**Alert Conditions**:
- 10x burn rate (5m window) → Critical, error budget exhausted in 3 days
- 3x burn rate (1h window) → Warning, error budget exhausted in 10 days

**Example Query**:
```promql
# Success rate
rate(weather_request_success_total{success="true"}[5m]) / 
rate(weather_request_success_total[5m])

# Error budget burn rate (for 99.9% SLO)
(1 - rate(weather_request_success_total{success="true"}[5m]) / rate(weather_request_success_total[5m])) / 0.001
```

## 📝 Logging Strategy

### Structured Logging (zerolog)

All logs are JSON-formatted for easy parsing and indexing:

```json
{
  "level": "info",
  "correlation_id": "550e8400-e29b-41d4-a716-446655440000",
  "method": "GET",
  "path": "/weather/London",
  "remote_addr": "192.168.1.1",
  "duration": 145.2,
  "status": 200,
  "timestamp": "2026-02-06T19:30:00Z",
  "message": "Request completed"
}
```

### Correlation IDs

Every request gets a UUID correlation ID for distributed tracing:
- Generated at entry point or from `X-Correlation-ID` header
- Propagated through all logs and downstream calls
- Enables full request path tracing

### Security: No Sensitive Data

**Never logged**:
- API keys (filtered from all outputs)
- User credentials
- PII (Personally Identifiable Information)
- Payment information

**What we DO log**:
- Request paths and methods
- Response status codes and latencies
- Error messages (sanitized)
- Correlation IDs
- Cache hit/miss decisions

### Log Levels

- **DEBUG**: Cache operations, retry attempts
- **INFO**: Request start/completion, successful operations
- **WARN**: Retry attempts, cache failures (service continues)
- **ERROR**: Failed requests, upstream errors
- **FATAL**: Service startup failures

## 🔔 Alerting Strategy

See `deployments/prometheus/rules.yml` and `deployments/prometheus/alertmanager.yml` for complete configuration.

### Alert Severity Tiers

**Critical (Page SRE)**:
- Service down >1 minute
- Error budget burn rate >10x (budget exhausted in 3 days)
- Upstream API completely down (>90% errors for 2min)
- P99 latency >5s for 2 minutes
- ANY cache errors

**Warning (Create Ticket)**:
- Error budget burn rate >3x (budget exhausted in 10 days)
- High error rate (>10% for 5min)
- P95 latency >500ms for 5 minutes
- Low cache hit rate (<50% for 10min)
- High retry rate (>5/sec for 5min)

### Multi-Window, Multi-Burn-Rate Alerting

Following Google SRE best practices:

```yaml
# Fast burn (short window, high burn rate) - Page immediately
- alert: HighErrorBudgetBurnRate
  expr: (1 - rate(weather_request_success_total{success="true"}[5m])) / 0.001 > 10
  for: 5m
  severity: critical

# Slow burn (longer window, lower burn rate) - Create ticket
- alert: MediumErrorBudgetBurnRate
  expr: (1 - rate(weather_request_success_total{success="true"}[1h])) / 0.001 > 3
  for: 15m
  severity: warning
```

## 📈 Dashboards

### Key Metrics to Display

**Golden Signals Dashboard**:
1. Request rate (requests/sec)
2. Error rate (%)
3. P50/P95/P99 latency
4. Success rate / SLO compliance

**RED Dashboard (by endpoint)**:
- Rate: Requests per second
- Errors: Error rate %
- Duration: P95/P99 latency

**USE Dashboard (resource utilization)**:
- Utilization: In-flight requests
- Saturation: Queue depth (if applicable)
- Errors: Error rate by type

**Cache Performance**:
- Hit ratio %
- Operations per second
- Error rate
- Size growth

## 🎯 SLI/SLO Definitions

See `docs/SLO.md` for complete details.

**Availability SLO**: 99.9% (43.2 minutes downtime per month)
**Latency SLO**: P95 < 500ms, P99 < 1s
**Error Rate SLO**: <0.1% over 5 minutes

## 🔍 Troubleshooting with Metrics

### High Latency
1. Check `weather_http_request_duration_seconds` P95/P99
2. Check `weather_api_request_duration_seconds` → Upstream slow?
3. Check `weather_cache_hits_total` ratio → Cache effective?
4. Check `weather_http_requests_in_flight` → Saturation?

### High Error Rate
1. Check `weather_http_requests_total` by status code
2. Check `weather_api_requests_total` → Upstream errors?
3. Check `weather_cache_errors_total` → Cache down?
4. Check logs with correlation ID for specific request

### Cache Issues
1. Check `weather_cache_errors_total` → Redis connectivity?
2. Check hit ratio → TTL too short?
3. Check `weather_cache_size` → Memory issues?

## 🏗️ Production Readiness Checklist

- ✅ All critical paths instrumented
- ✅ Metrics follow naming conventions
- ✅ Each metric has clear use case and alert conditions
- ✅ Structured logging with correlation IDs
- ✅ No sensitive data in logs
- ✅ Alert runbooks created
- ✅ SLO targets defined
- ✅ Dashboards created
- ✅ On-call rotation established
- ✅ Incident response procedures documented
