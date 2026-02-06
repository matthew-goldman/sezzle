package api

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/matthew-goldman/sezzle/internal/cache"
	"github.com/matthew-goldman/sezzle/internal/config"
	"github.com/matthew-goldman/sezzle/internal/metrics"
	"github.com/matthew-goldman/sezzle/internal/weather"
	"github.com/rs/zerolog/log"
	"golang.org/x/time/rate"
)

// Handler contains dependencies for API handlers
type Handler struct {
	weatherClient *weather.Client
	cache         cache.Cache
	config        *config.Config
}

// NewHandler creates a new API handler
func NewHandler(weatherClient *weather.Client, cache cache.Cache, cfg *config.Config) *Handler {
	return &Handler{
		weatherClient: weatherClient,
		cache:         cache,
		config:        cfg,
	}
}

// GetWeather handles GET /weather/{location}
func (h *Handler) GetWeather(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		respondError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	// Extract location from path
	location := strings.TrimPrefix(r.URL.Path, "/weather/")
	if location == "" || location == "/weather/" {
		respondError(w, http.StatusBadRequest, "Location is required")
		return
	}

	correlationID := r.Context().Value("correlation_id")
	ctx := context.WithValue(r.Context(), "correlation_id", correlationID)

	log.Info().
		Str("correlation_id", fmt.Sprintf("%v", correlationID)).
		Str("location", location).
		Msg("Fetching weather data")

	// Try cache first
	cacheKey := fmt.Sprintf("weather:%s", location)
	var weatherData weather.WeatherData

	err := h.cache.Get(ctx, cacheKey, &weatherData)
	if err == nil {
		log.Info().
			Str("correlation_id", fmt.Sprintf("%v", correlationID)).
			Str("location", location).
			Msg("Cache hit")
		respondJSON(w, http.StatusOK, weatherData)
		return
	}

	// Cache miss - fetch from API
	log.Info().
		Str("correlation_id", fmt.Sprintf("%v", correlationID)).
		Str("location", location).
		Msg("Cache miss, fetching from API")

	// Create context with timeout
	apiCtx, cancel := context.WithTimeout(ctx, h.config.Weather.Timeout)
	defer cancel()

	data, err := h.weatherClient.GetWeather(apiCtx, location)
	if err != nil {
		log.Error().
			Str("correlation_id", fmt.Sprintf("%v", correlationID)).
			Str("location", location).
			Err(err).
			Msg("Failed to fetch weather data")
		respondError(w, http.StatusServiceUnavailable, "Failed to fetch weather data")
		return
	}

	// Store in cache
	if err := h.cache.Set(ctx, cacheKey, data, h.config.Cache.TTL); err != nil {
		log.Warn().
			Str("correlation_id", fmt.Sprintf("%v", correlationID)).
			Err(err).
			Msg("Failed to cache weather data")
		// Continue anyway - cache failure shouldn't fail the request
	}

	respondJSON(w, http.StatusOK, data)
}

// Health handles GET /health
func (h *Handler) Health(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		respondError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	health := map[string]interface{}{
		"status":    "healthy",
		"timestamp": time.Now().Unix(),
		"version":   h.config.Version,
	}

	respondJSON(w, http.StatusOK, health)
}

// respondJSON writes a JSON response
func respondJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

// respondError writes an error response
func respondError(w http.ResponseWriter, status int, message string) {
	respondJSON(w, status, map[string]string{"error": message})
}

// Middleware chain

// Chain applies middleware to a handler
func Chain(handler http.Handler, cfg *config.Config) http.Handler {
	// Apply middleware in reverse order (last middleware wraps first)
	handler = loggingMiddleware(handler)
	handler = metricsMiddleware(handler)
	handler = correlationIDMiddleware(handler)
	
	if cfg.RateLimit.Enabled {
		handler = rateLimitMiddleware(handler, cfg.RateLimit.RequestsPerSecond, cfg.RateLimit.Burst)
	}
	
	handler = recoveryMiddleware(handler)
	
	return handler
}

// correlationIDMiddleware adds a correlation ID to each request
func correlationIDMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		correlationID := r.Header.Get("X-Correlation-ID")
		if correlationID == "" {
			correlationID = uuid.New().String()
		}

		// Add to response headers
		w.Header().Set("X-Correlation-ID", correlationID)

		// Add to context
		ctx := context.WithValue(r.Context(), "correlation_id", correlationID)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// loggingMiddleware logs requests with structured logging
func loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		correlationID := r.Context().Value("correlation_id")

		// Create response writer wrapper to capture status code
		wrapped := &responseWriter{ResponseWriter: w, statusCode: http.StatusOK}

		log.Info().
			Str("correlation_id", fmt.Sprintf("%v", correlationID)).
			Str("method", r.Method).
			Str("path", r.URL.Path).
			Str("remote_addr", r.RemoteAddr).
			Msg("Request started")

		next.ServeHTTP(wrapped, r)

		duration := time.Since(start)

		log.Info().
			Str("correlation_id", fmt.Sprintf("%v", correlationID)).
			Str("method", r.Method).
			Str("path", r.URL.Path).
			Int("status", wrapped.statusCode).
			Dur("duration", duration).
			Msg("Request completed")
	})
}

// metricsMiddleware records Prometheus metrics
func metricsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		metrics.IncHTTPInFlight()
		defer metrics.DecHTTPInFlight()

		// Create response writer wrapper to capture status code
		wrapped := &responseWriter{ResponseWriter: w, statusCode: http.StatusOK}

		next.ServeHTTP(wrapped, r)

		duration := time.Since(start).Seconds()
		endpoint := normalizeEndpoint(r.URL.Path)
		
		metrics.RecordHTTPRequest(
			r.Method,
			endpoint,
			fmt.Sprintf("%d", wrapped.statusCode),
			duration,
		)
	})
}

// rateLimitMiddleware implements rate limiting
func rateLimitMiddleware(next http.Handler, rps float64, burst int) http.Handler {
	limiter := rate.NewLimiter(rate.Limit(rps), burst)

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !limiter.Allow() {
			endpoint := normalizeEndpoint(r.URL.Path)
			metrics.RecordRateLimitExceeded(endpoint)
			
			log.Warn().
				Str("correlation_id", fmt.Sprintf("%v", r.Context().Value("correlation_id"))).
				Str("path", r.URL.Path).
				Msg("Rate limit exceeded")
			
			respondError(w, http.StatusTooManyRequests, "Rate limit exceeded")
			return
		}

		next.ServeHTTP(w, r)
	})
}

// recoveryMiddleware recovers from panics
func recoveryMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if err := recover(); err != nil {
				log.Error().
					Str("correlation_id", fmt.Sprintf("%v", r.Context().Value("correlation_id"))).
					Interface("panic", err).
					Msg("Panic recovered")
				
				respondError(w, http.StatusInternalServerError, "Internal server error")
			}
		}()

		next.ServeHTTP(w, r)
	})
}

// responseWriter wraps http.ResponseWriter to capture status code
type responseWriter struct {
	http.ResponseWriter
	statusCode int
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}

// normalizeEndpoint normalizes paths for consistent metrics
func normalizeEndpoint(path string) string {
	if strings.HasPrefix(path, "/weather/") {
		return "/weather/{location}"
	}
	return path
}
