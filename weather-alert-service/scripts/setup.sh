#!/bin/bash
set -e

echo "🌤️  Weather Alert Service - Quick Setup"
echo "======================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if Go is installed
if ! command -v go &> /dev/null; then
    echo -e "${RED}❌ Go is not installed. Please install Go 1.21 or later.${NC}"
    echo "Visit: https://golang.org/doc/install"
    exit 1
fi

echo -e "${GREEN}✓ Go is installed: $(go version)${NC}"

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}⚠️  Docker is not installed. Docker is recommended for local development.${NC}"
    echo "Visit: https://docs.docker.com/get-docker/"
else
    echo -e "${GREEN}✓ Docker is installed: $(docker --version)${NC}"
fi

# Check if OpenWeatherMap API key is set
if [ -z "$OPENWEATHER_API_KEY" ]; then
    echo ""
    echo -e "${YELLOW}⚠️  OPENWEATHER_API_KEY environment variable is not set.${NC}"
    echo "Please get a free API key from: https://openweathermap.org/api"
    echo ""
    read -p "Enter your OpenWeatherMap API key (or press Enter to skip): " API_KEY
    
    if [ ! -z "$API_KEY" ]; then
        export OPENWEATHER_API_KEY="$API_KEY"
        echo "export OPENWEATHER_API_KEY=\"$API_KEY\"" >> .env
        echo -e "${GREEN}✓ API key saved to .env file${NC}"
    fi
else
    echo -e "${GREEN}✓ OPENWEATHER_API_KEY is set${NC}"
fi

# Copy .env.example to .env if it doesn't exist
if [ ! -f .env ]; then
    echo ""
    echo "Creating .env file from .env.example..."
    cp .env.example .env
    if [ ! -z "$OPENWEATHER_API_KEY" ]; then
        sed -i.bak "s/your_api_key_here/$OPENWEATHER_API_KEY/" .env
        rm .env.bak
    fi
    echo -e "${GREEN}✓ .env file created${NC}"
fi

# Download Go dependencies
echo ""
echo "Downloading Go dependencies..."
go mod download
echo -e "${GREEN}✓ Dependencies downloaded${NC}"

# Run tests
echo ""
echo "Running tests..."
if go test ./... -v; then
    echo -e "${GREEN}✓ All tests passed${NC}"
else
    echo -e "${RED}❌ Some tests failed${NC}"
fi

# Build the application
echo ""
echo "Building application..."
if make build; then
    echo -e "${GREEN}✓ Application built successfully${NC}"
else
    echo -e "${RED}❌ Build failed${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ Setup complete!${NC}"
echo ""
echo "Next steps:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Start the development environment:"
echo "   ${YELLOW}make dev${NC}"
echo ""
echo "2. Or run locally without Docker:"
echo "   ${YELLOW}make run${NC}"
echo ""
echo "3. Test the service:"
echo "   ${YELLOW}curl http://localhost:8080/health${NC}"
echo "   ${YELLOW}curl http://localhost:8080/weather/London${NC}"
echo ""
echo "4. View metrics:"
echo "   ${YELLOW}curl http://localhost:8080/metrics${NC}"
echo ""
echo "5. Access monitoring (if using docker-compose):"
echo "   Prometheus: http://localhost:9090"
echo "   Grafana:    http://localhost:3000 (admin/admin)"
echo ""
echo "For more information, see README.md"
