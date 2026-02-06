package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/matthew-goldman/sezzle/internal/api"
	"github.com/matthew-goldman/sezzle/internal/cache"
	"github.com/matthew-goldman/sezzle/internal/config"
	"github.com/matthew-goldman/sezzle/internal/metrics"
	"github.com/matthew-goldman/sezzle/internal/weather"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
)

func main() {
	// Initialize structured logging
	zerolog.TimeFieldFormat = zerolog.TimeFormatUnix
	log.Logger = log.Output(zerolog.ConsoleWriter{Out: os.Stderr, TimeFormat: time.RFC3339})

	// Load configuration
	cfg, err := config.Load()
	if err != nil {
		log.Fatal().Err(err).Msg("Failed to load configuration")
	}

	// Set log level from config
	level, err := zerolog.ParseLevel(cfg.LogLevel)
	if err != nil {
		level = zerolog.InfoLevel
	}
	zerolog.SetGlobalLevel(level)

	log.Info().
		Str("version", cfg.Version).
		Str("environment", cfg.Environment).
		Msg("Starting Weather Alert Service")

	// Initialize metrics
	metrics.Init()

	// Initialize cache
	var cacheStore cache.Cache
	if cfg.Cache.Type == "redis" {
		cacheStore, err = cache.NewRedisCache(cfg.Cache.RedisAddr, cfg.Cache.RedisPassword, cfg.Cache.TTL)
		if err != nil {
			log.Fatal().Err(err).Msg("Failed to initialize Redis cache")
		}
	} else {
		cacheStore = cache.NewMemoryCache(cfg.Cache.TTL)
	}
	defer cacheStore.Close()

	// Initialize weather client
	weatherClient := weather.NewClient(cfg.Weather.APIKey, cfg.Weather.BaseURL, cfg.Weather.Timeout)

	// Initialize handlers
	handler := api.NewHandler(weatherClient, cacheStore, cfg)

	// Setup HTTP server with middleware
	mux := http.NewServeMux()

	// API endpoints
	mux.HandleFunc("/weather/", handler.GetWeather)
	mux.HandleFunc("/health", handler.Health)

	// Metrics endpoint (Prometheus)
	mux.Handle("/metrics", promhttp.Handler())

	// Wrap with middleware
	server := &http.Server{
		Addr:         fmt.Sprintf(":%d", cfg.Server.Port),
		Handler:      api.Chain(mux, cfg),
		ReadTimeout:  cfg.Server.ReadTimeout,
		WriteTimeout: cfg.Server.WriteTimeout,
		IdleTimeout:  cfg.Server.IdleTimeout,
	}

	// Start server in goroutine
	go func() {
		log.Info().Int("port", cfg.Server.Port).Msg("Server starting")
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatal().Err(err).Msg("Server failed to start")
		}
	}()

	// Graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Info().Msg("Server shutting down gracefully...")

	// Give outstanding requests time to complete
	ctx, cancel := context.WithTimeout(context.Background(), cfg.Server.ShutdownTimeout)
	defer cancel()

	if err := server.Shutdown(ctx); err != nil {
		log.Error().Err(err).Msg("Server forced to shutdown")
	}

	log.Info().Msg("Server stopped")
}
