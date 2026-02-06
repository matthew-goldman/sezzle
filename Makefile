.PHONY: help build test lint clean docker-build docker-up docker-down deploy run

# Variables
APP_NAME := weather-service
VERSION := $(shell git describe --tags --always --dirty)
DOCKER_IMAGE := $(APP_NAME):$(VERSION)
GO_FILES := $(shell find . -type f -name '*.go')

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build: ## Build the application binary
	@echo "Building $(APP_NAME)..."
	@CGO_ENABLED=0 go build -ldflags="-s -w -X main.version=$(VERSION)" -o bin/$(APP_NAME) ./cmd/server

run: ## Run the application locally
	@echo "Running $(APP_NAME)..."
	@go run cmd/server/main.go

test: ## Run tests with coverage
	@echo "Running tests..."
	@go test -v -race -coverprofile=coverage.out ./...
	@go tool cover -func=coverage.out

test-coverage: test ## Generate and open coverage report
	@go tool cover -html=coverage.out

lint: ## Run linters
	@echo "Running linters..."
	@which golangci-lint > /dev/null || (echo "Installing golangci-lint..." && go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest)
	@golangci-lint run ./...

fmt: ## Format code
	@echo "Formatting code..."
	@go fmt ./...
	@goimports -w .

vet: ## Run go vet
	@echo "Running go vet..."
	@go vet ./...

tidy: ## Tidy go modules
	@echo "Tidying go modules..."
	@go mod tidy

deps: ## Download dependencies
	@echo "Downloading dependencies..."
	@go mod download

clean: ## Clean build artifacts
	@echo "Cleaning..."
	@rm -rf bin/ coverage.out

docker-build: ## Build Docker image
	@echo "Building Docker image $(DOCKER_IMAGE)..."
	@docker build -t $(DOCKER_IMAGE) -t $(APP_NAME):latest .

docker-up: ## Start services with docker-compose
	@echo "Starting services..."
	@docker-compose up -d
	@echo "Services started. Application available at http://localhost:8080"
	@echo "Prometheus available at http://localhost:9090"
	@echo "Grafana available at http://localhost:3000"

docker-down: ## Stop services with docker-compose
	@echo "Stopping services..."
	@docker-compose down

docker-logs: ## Show docker-compose logs
	@docker-compose logs -f

docker-push: docker-build ## Push Docker image to registry
	@echo "Pushing $(DOCKER_IMAGE)..."
	@docker push $(DOCKER_IMAGE)

terraform-init: ## Initialize Terraform
	@cd deployments/terraform && terraform init

terraform-plan: ## Run Terraform plan
	@cd deployments/terraform && terraform plan

terraform-apply: ## Apply Terraform changes
	@cd deployments/terraform && terraform apply

terraform-destroy: ## Destroy Terraform infrastructure
	@cd deployments/terraform && terraform destroy

k8s-deploy: ## Deploy to Kubernetes
	@echo "Deploying to Kubernetes..."
	@kubectl apply -f deployments/kubernetes/

k8s-delete: ## Delete from Kubernetes
	@echo "Deleting from Kubernetes..."
	@kubectl delete -f deployments/kubernetes/

k8s-logs: ## Show Kubernetes logs
	@kubectl logs -f -n weather-service deployment/weather-service

benchmark: ## Run benchmarks
	@echo "Running benchmarks..."
	@go test -bench=. -benchmem ./...

security: ## Run security checks
	@echo "Running security checks..."
	@which gosec > /dev/null || (echo "Installing gosec..." && go install github.com/securego/gosec/v2/cmd/gosec@latest)
	@gosec ./...

mock-gen: ## Generate mocks for testing
	@echo "Generating mocks..."
	@which mockgen > /dev/null || (echo "Installing mockgen..." && go install github.com/golang/mock/mockgen@latest)
	@mockgen -source=internal/cache/cache.go -destination=internal/cache/mock_cache.go -package=cache

install-tools: ## Install development tools
	@echo "Installing development tools..."
	@go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
	@go install github.com/securego/gosec/v2/cmd/gosec@latest
	@go install golang.org/x/tools/cmd/goimports@latest

check: lint vet test ## Run all checks (lint, vet, test)

ci: deps lint vet test ## Run CI pipeline locally

dev: docker-up ## Start development environment
	@echo "Development environment ready!"
	@echo ""
	@echo "Try these commands:"
	@echo "  curl http://localhost:8080/health"
	@echo "  curl http://localhost:8080/weather/London"
	@echo "  curl http://localhost:8080/metrics"

.DEFAULT_GOAL := help
