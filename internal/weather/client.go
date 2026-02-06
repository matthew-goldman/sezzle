package weather

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"

	"github.com/matthew-goldman/sezzle/internal/metrics"
	"github.com/rs/zerolog/log"
)

// Client handles communication with the OpenWeatherMap API
type Client struct {
	apiKey     string
	baseURL    string
	httpClient *http.Client
	maxRetries int
	retryDelay time.Duration
}

// WeatherData represents the weather information
type Data struct {
	Location    string  `json:"location"`
	Temperature float64 `json:"temperature"`
	Conditions  string  `json:"conditions"`
	Humidity    int     `json:"humidity"`
	WindSpeed   float64 `json:"wind_speed"`
	Timestamp   int64   `json:"timestamp"`
}

// OpenWeatherMapResponse represents the API response from OpenWeatherMap
type OpenWeatherMapResponse struct {
	Name string `json:"name"`
	Main struct {
		Temp     float64 `json:"temp"`
		Humidity int     `json:"humidity"`
	} `json:"main"`
	Weather []struct {
		Main        string `json:"main"`
		Description string `json:"description"`
	} `json:"weather"`
	Wind struct {
		Speed float64 `json:"speed"`
	} `json:"wind"`
}

// NewClient creates a new weather API client
func NewClient(apiKey, baseURL string, timeout time.Duration) *Client {
	return &Client{
		apiKey:  apiKey,
		baseURL: baseURL,
		httpClient: &http.Client{
			Timeout: timeout,
		},
		maxRetries: 3,
		retryDelay: 1 * time.Second,
	}
}

// GetWeather retrieves weather data for a location with retry logic
func (c *Client) GetWeather(ctx context.Context, location string) (*Data, error) {
	var lastErr error

	// Correlation ID for tracing
	correlationID := ctx.Value("correlation_id")

	for attempt := 0; attempt <= c.maxRetries; attempt++ {
		if attempt > 0 {
			// Exponential backoff
			delay := c.retryDelay * time.Duration(1<<min(attempt-1, 10))
			if delay > 10*time.Second {
				delay = 10 * time.Second
			}

			log.Warn().
				Str("correlation_id", fmt.Sprintf("%v", correlationID)).
				Str("location", location).
				Int("attempt", attempt).
				Dur("delay", delay).
				Err(lastErr).
				Msg("Retrying weather API request")

			metrics.RecordWeatherAPIRetry(location, fmt.Sprintf("%v", lastErr))

			select {
			case <-time.After(delay):
			case <-ctx.Done():
				return nil, ctx.Err()
			}
		}

		start := time.Now()
		data, err := c.fetchWeather(ctx, location)
		duration := time.Since(start).Seconds()

		if err == nil {
			metrics.RecordWeatherAPIRequest("success", location, duration)
			log.Info().
				Str("correlation_id", fmt.Sprintf("%v", correlationID)).
				Str("location", location).
				Float64("temperature", data.Temperature).
				Dur("duration", time.Since(start)).
				Msg("Successfully fetched weather data")
			return data, nil
		}

		lastErr = err
		metrics.RecordWeatherAPIRequest("error", location, duration)

		// Don't retry on context cancellation or certain errors
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}

		// Check if error is retryable (5xx errors, timeouts)
		if !isRetryable(err) {
			log.Error().
				Str("correlation_id", fmt.Sprintf("%v", correlationID)).
				Str("location", location).
				Err(err).
				Msg("Non-retryable error from weather API")
			return nil, err
		}
	}

	log.Error().
		Str("correlation_id", fmt.Sprintf("%v", correlationID)).
		Str("location", location).
		Int("attempts", c.maxRetries+1).
		Err(lastErr).
		Msg("All retry attempts exhausted")

	return nil, fmt.Errorf("failed after %d attempts: %w", c.maxRetries+1, lastErr)
}

// fetchWeather makes a single request to the weather API
func (c *Client) fetchWeather(ctx context.Context, location string) (*Data, error) {
	// Build request URL
	apiURL := fmt.Sprintf("%s/weather", c.baseURL)
	params := url.Values{}
	params.Add("q", location)
	params.Add("appid", c.apiKey)
	params.Add("units", "metric")

	fullURL := fmt.Sprintf("%s?%s", apiURL, params.Encode())

	// Create request with context
	req, err := http.NewRequestWithContext(ctx, "GET", fullURL, http.NoBody)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	// Make the request
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to make request: %w", err)
	}
	defer resp.Body.Close()

	// Read response body
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	// Check status code
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("API returned status %d: %s", resp.StatusCode, string(body))
	}

	// Parse response
	var apiResp OpenWeatherMapResponse
	if err := json.Unmarshal(body, &apiResp); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	// Convert to our format
	data := &Data{
		Location:    apiResp.Name,
		Temperature: apiResp.Main.Temp,
		Humidity:    apiResp.Main.Humidity,
		WindSpeed:   apiResp.Wind.Speed,
		Timestamp:   time.Now().Unix(),
	}

	if len(apiResp.Weather) > 0 {
		data.Conditions = apiResp.Weather[0].Description
	}

	return data, nil
}

// isRetryable determines if an error should trigger a retry
func isRetryable(err error) bool {
	// Retry on network errors and 5xx status codes
	// Don't retry on 4xx errors (client errors)
	if err == nil {
		return false
	}

	errStr := err.Error()

	// Timeout errors are retryable
	if ctx, ok := err.(interface{ Timeout() bool }); ok && ctx.Timeout() {
		return true
	}

	// 5xx errors are retryable
	if errStr != "" && errStr[0] == '5' {
		return true
	}

	// Network errors are retryable
	return true
}
