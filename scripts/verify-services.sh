#!/bin/bash

# Odin's Eye Service Verification Script
# Tests all deployed Docker services

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 Odin's Eye Service Verification${NC}"
echo "=================================="
echo

# Function to test service
test_service() {
    local service_name=$1
    local test_command=$2
    local description=$3

    echo -n "Testing $service_name... "
    if eval "$test_command" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ PASS${NC}"
        echo "  $description"
    else
        echo -e "${RED}❌ FAIL${NC}"
        echo "  $description"
        return 1
    fi
    echo
}

# Function to test web service
test_web_service() {
    local service_name=$1
    local url=$2
    local description=$3

    echo -n "Testing $service_name... "
    if curl -s -f "$url" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ PASS${NC}"
        echo "  $description"
    else
        echo -e "${RED}❌ FAIL${NC}"
        echo "  $description"
        return 1
    fi
    echo
}

# Check if we're in the right directory
if [[ ! -f "docker-compose.yml" ]]; then
    echo -e "${RED}❌ Error: docker-compose.yml not found${NC}"
    echo "Please run this script from the docker directory"
    exit 1
fi

# Test Docker Compose
echo -e "${BLUE}=== Docker Services ===${NC}"
test_service "Docker Compose" "docker compose ps" "Check if all containers are running"

# Test individual containers
echo -e "${BLUE}=== Container Health ===${NC}"

# Test main AI app
test_web_service "Main AI Dashboard" "http://localhost:8080/api/health" "FastAPI health endpoint"

# Test Jupyter Lab
test_web_service "Jupyter Lab" "http://localhost:8888" "Jupyter Lab web interface"

# Test Grafana
test_web_service "Grafana" "http://localhost:3001" "Grafana dashboard"

# Test Prometheus
test_web_service "Prometheus" "http://localhost:9090" "Prometheus metrics"

# Test Node Exporter
test_web_service "Node Exporter" "http://localhost:9100/metrics" "System metrics endpoint"

# Test PostgreSQL
test_service "PostgreSQL" "docker exec odins-eye-postgres psql -U odin -d odins_eye -c 'SELECT 1;'" "Database connection"

# Test Redis
test_service "Redis" "docker exec odins-eye-redis redis-cli ping" "Redis cache connection"

# Test Nginx
test_web_service "Nginx" "http://localhost:80" "Nginx reverse proxy"

echo -e "${BLUE}=== Service Details ===${NC}"

# Show container status
echo -e "${YELLOW}Container Status:${NC}"
docker compose ps

echo
echo -e "${YELLOW}Service URLs:${NC}"
echo "  Main Dashboard: http://localhost:8080"
echo "  Grafana:        http://localhost:3001 (admin/admin)"
echo "  Jupyter Lab:    http://localhost:8888"
echo "  Prometheus:     http://localhost:9090"
echo "  Node Exporter:  http://localhost:9100"

echo
echo -e "${GREEN}🎉 Service verification complete!${NC}"
echo "All services should be accessible via the URLs above."
