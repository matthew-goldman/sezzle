package metrics

import (
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

var (
	// HTTP Request Metrics
	
	// httpRequestsTotal tracks the total number of HTTP requests received
	// USE CASE: Track request volume and identify traffic patterns
	// ALERT: Sudden drops may indicate service unavailability or upstream issues
	httpRequestsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "weather_http_requests_total",
			Help: "Total number of HTTP requests received",
		},
		[]string{"method", "endpoint", "status"},
	)

	// httpRequestDuration tracks the latency distribution of HTTP requests
	// USE CASE: Monitor API response times and identify performance degradation
	// ALERT: P95/P99 latency spikes indicate performance issues requiring investigation
	httpRequestDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "weather_http_request_duration_seconds",
			Help:    "HTTP request latency distribution",
			Buckets: prometheus.DefBuckets, // 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10
		},
		[]string{"method", "endpoint"},
	)

	// httpRequestsInFlight tracks currently active HTTP requests
	// USE CASE: Monitor concurrent request load and identify saturation
	// ALERT: Sustained high values may indicate slow downstream services or need for scaling
	httpRequestsInFlight = promauto.NewGauge(
		prometheus.GaugeOpts{
			Name: "weather_http_requests_in_flight",
			Help: "Current number of HTTP requests being processed",
		},
	)

	// Weather API Client Metrics

	// weatherAPIRequestsTotal tracks requests made to the upstream weather API
	// USE CASE: Monitor API usage and detect integration issues
	// ALERT: High error rates indicate upstream API problems or misconfigurations
	weatherAPIRequestsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "weather_api_requests_total",
			Help: "Total number of requests to weather API",
		},
		[]string{"status", "location"},
	)

	// weatherAPIRequestDuration tracks latency of weather API calls
	// USE CASE: Monitor upstream API performance and detect degradation
	// ALERT: Latency increases may require cache TTL adjustments or circuit breaker activation
	weatherAPIRequestDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "weather_api_request_duration_seconds",
			Help:    "Weather API request latency distribution",
			Buckets: []float64{.1, .25, .5, 1, 2.5, 5, 10}, // Focused on external API latency
		},
		[]string{"location"},
	)

	// weatherAPIRetries tracks retry attempts for failed API calls
	// USE CASE: Monitor reliability and identify when retry logic is triggered
	// ALERT: High retry rates indicate unstable upstream service requiring investigation
	weatherAPIRetries = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "weather_api_retries_total",
			Help: "Total number of retry attempts for weather API calls",
		},
		[]string{"location", "reason"},
	)

	// Cache Metrics

	// cacheHits tracks successful cache retrievals
	// USE CASE: Measure cache effectiveness and optimize cache strategy
	// ALERT: Low hit rates may indicate TTL too short or cache eviction issues
	cacheHits = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "weather_cache_hits_total",
			Help: "Total number of cache hits",
		},
		[]string{"cache_type"},
	)

	// cacheMisses tracks cache misses requiring upstream calls
	// USE CASE: Identify cache efficiency and guide capacity planning
	// ALERT: Sudden increases may indicate cache failure or invalidation issues
	cacheMisses = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "weather_cache_misses_total",
			Help: "Total number of cache misses",
		},
		[]string{"cache_type"},
	)

	// cacheErrors tracks cache operation failures
	// USE CASE: Monitor cache infrastructure health
	// ALERT: Any cache errors require immediate investigation (Redis down, memory issues)
	cacheErrors = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "weather_cache_errors_total",
			Help: "Total number of cache operation errors",
		},
		[]string{"cache_type", "operation"},
	)

	// cacheSize tracks current number of items in cache
	// USE CASE: Monitor cache growth and memory usage
	// ALERT: Unexpected growth may indicate cache key issues or memory leaks
	cacheSize = promauto.NewGauge(
		prometheus.GaugeOpts{
			Name: "weather_cache_size",
			Help: "Current number of items in cache",
		},
	)

	// Rate Limiting Metrics

	// rateLimitExceeded tracks requests rejected by rate limiter
	// USE CASE: Monitor rate limit effectiveness and identify potential abuse
	// ALERT: High rejection rates may indicate DDoS or need for rate limit adjustment
	rateLimitExceeded = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "weather_rate_limit_exceeded_total",
			Help: "Total number of requests rejected by rate limiter",
		},
		[]string{"endpoint"},
	)

	// Circuit Breaker Metrics (if implemented)

	// circuitBreakerState tracks current circuit breaker status
	// USE CASE: Monitor circuit breaker activations and service degradation
	// ALERT: Open state indicates upstream failures requiring immediate attention
	circuitBreakerState = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "weather_circuit_breaker_state",
			Help: "Circuit breaker state (0=closed, 1=open, 2=half-open)",
		},
		[]string{"service"},
	)

	// SLI Metrics for SLO Tracking

	// requestSuccessRate tracks successful vs failed requests for SLI calculation
	// USE CASE: Calculate availability SLI for SLO compliance (e.g., 99.9% success rate)
	// ALERT: SLO burn rate alerts when error budget is consumed too quickly
	requestSuccessRate = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "weather_request_success_total",
			Help: "Total number of successful requests (for SLI calculation)",
		},
		[]string{"success"}, // "true" or "false"
	)
)

// Init initializes the metrics registry (called at startup)
func Init() {
	// Metrics are automatically registered via promauto
	// This function exists for explicit initialization if needed
}

// RecordHTTPRequest records metrics for an HTTP request
func RecordHTTPRequest(method, endpoint, status string, duration float64) {
	httpRequestsTotal.WithLabelValues(method, endpoint, status).Inc()
	httpRequestDuration.WithLabelValues(method, endpoint).Observe(duration)
	
	// Track success for SLI
	success := "true"
	if status[0] == '5' || status[0] == '4' { // 4xx and 5xx are failures
		success = "false"
	}
	requestSuccessRate.WithLabelValues(success).Inc()
}

// IncHTTPInFlight increments in-flight request counter
func IncHTTPInFlight() {
	httpRequestsInFlight.Inc()
}

// DecHTTPInFlight decrements in-flight request counter
func DecHTTPInFlight() {
	httpRequestsInFlight.Dec()
}

// RecordWeatherAPIRequest records metrics for a weather API call
func RecordWeatherAPIRequest(status, location string, duration float64) {
	weatherAPIRequestsTotal.WithLabelValues(status, location).Inc()
	weatherAPIRequestDuration.WithLabelValues(location).Observe(duration)
}

// RecordWeatherAPIRetry records a retry attempt
func RecordWeatherAPIRetry(location, reason string) {
	weatherAPIRetries.WithLabelValues(location, reason).Inc()
}

// RecordCacheHit records a cache hit
func RecordCacheHit(cacheType string) {
	cacheHits.WithLabelValues(cacheType).Inc()
}

// RecordCacheMiss records a cache miss
func RecordCacheMiss(cacheType string) {
	cacheMisses.WithLabelValues(cacheType).Inc()
}

// RecordCacheError records a cache error
func RecordCacheError(cacheType, operation string) {
	cacheErrors.WithLabelValues(cacheType, operation).Inc()
}

// SetCacheSize updates the cache size gauge
func SetCacheSize(size float64) {
	cacheSize.Set(size)
}

// RecordRateLimitExceeded records a rate limit rejection
func RecordRateLimitExceeded(endpoint string) {
	rateLimitExceeded.WithLabelValues(endpoint).Inc()
}

// SetCircuitBreakerState sets the circuit breaker state
// 0 = closed (healthy), 1 = open (failing), 2 = half-open (testing)
func SetCircuitBreakerState(service string, state float64) {
	circuitBreakerState.WithLabelValues(service).Set(state)
}
