#!/bin/bash

# Odin's AI Docker Verification Script
# Tests the containerized deployment instead of bare metal services

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test function
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_output="$3"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -n "Testing $test_name... "

    if eval "$test_command" | grep -q "$expected_output" 2>/dev/null; then
        echo -e "${GREEN}✓ PASS${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

# Web service test function
test_web_service() {
    local service_name="$1"
    local url="$2"
    local expected_content="$3"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -n "Testing $service_name... "

    if curl -s --max-time 10 "$url" | grep -q "$expected_content" 2>/dev/null; then
        echo -e "${GREEN}✓ PASS${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

# Docker container tests
test_containers() {
    echo -e "\n${BLUE}=== Docker Container Tests ===${NC}"

    # Check if Docker Compose is running
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -n "Testing Docker Compose status... "
    if cd docker && docker compose ps | grep -q "Up" 2>/dev/null; then
        echo -e "${GREEN}✓ PASS${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    cd ..

    # Test individual containers
    local containers=("odins-eye" "odins-eye-jupyter" "odins-eye-grafana" "odins-eye-postgres" "odins-eye-redis" "odins-eye-prometheus" "odins-eye-node-exporter" "odins-eye-nginx")

    for container in "${containers[@]}"; do
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        echo -n "Testing $container... "
        if docker ps --format "table {{.Names}}" | grep -q "$container" 2>/dev/null; then
            echo -e "${GREEN}✓ PASS${NC}"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo -e "${RED}✗ FAIL${NC}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    done
}

# Service endpoint tests
test_endpoints() {
    echo -e "\n${BLUE}=== Service Endpoint Tests ===${NC}"

    # Test main AI application
    test_web_service "Main AI Dashboard" "http://localhost:8080/api/health" "healthy"

    # Test Jupyter Lab
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -n "Testing Jupyter Lab... "
    if curl -s -I http://localhost:8888 | grep -q "TornadoServer" 2>/dev/null; then
        echo -e "${GREEN}✓ PASS${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi

    # Test Grafana
    test_web_service "Grafana" "http://localhost:3001" "login"

    # Test Prometheus
    test_web_service "Prometheus" "http://localhost:9090" "graph"

    # Test Node Exporter
    test_web_service "Node Exporter" "http://localhost:9100/metrics" "node_"
}

# GPU tests
test_gpu() {
    echo -e "\n${BLUE}=== GPU Tests ===${NC}"

    # Test GPU access from host
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -n "Testing host GPU access... "
    if nvidia-smi >/dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi

    # Test GPU access from main container
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -n "Testing GPU in main container... "
    if docker exec odins-eye nvidia-smi >/dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi

    # Test GPU access from Jupyter container
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -n "Testing GPU in Jupyter container... "
    if docker exec odins-eye-jupyter nvidia-smi >/dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

# Database tests
test_databases() {
    echo -e "\n${BLUE}=== Database Tests ===${NC}"

    # Test PostgreSQL
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -n "Testing PostgreSQL... "
    if docker exec odins-eye-postgres psql -U odin -d odins_eye -c "SELECT 1;" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi

    # Test Redis
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -n "Testing Redis... "
    if docker exec odins-eye-redis redis-cli ping | grep -q "PONG" 2>/dev/null; then
        echo -e "${GREEN}✓ PASS${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

# AI framework tests
test_ai_frameworks() {
    echo -e "\n${BLUE}=== AI Framework Tests ===${NC}"

    # Test PyTorch in main container
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -n "Testing PyTorch in main container... "
    if docker exec odins-eye python3 -c "import torch; print(torch.cuda.is_available())" | grep -q "True" 2>/dev/null; then
        echo -e "${GREEN}✓ PASS${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi

    # Test TensorFlow in Jupyter container
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -n "Testing TensorFlow in Jupyter container... "
    if docker exec odins-eye-jupyter python3 -c "import tensorflow as tf; print(tf.config.list_physical_devices('GPU'))" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

# Network tests
test_networking() {
    echo -e "\n${BLUE}=== Network Tests ===${NC}"

    # Test container networking
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -n "Testing container network... "
    if docker network ls | grep -q "odins-eye-network" 2>/dev/null; then
        echo -e "${GREEN}✓ PASS${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi

    # Test inter-container communication
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -n "Testing inter-container communication... "
    if docker exec odins-eye-postgres psql -U odin -d odins_eye -c "SELECT 1;" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

# Print summary
print_summary() {
    echo -e "\n${BLUE}=== Docker Verification Summary ===${NC}"
    echo -e "Total tests: $TOTAL_TESTS"
    echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
    echo -e "Failed: ${RED}$FAILED_TESTS${NC}"

    local success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    echo -e "Success rate: ${success_rate}%"

    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "\n${GREEN}🎉 All Docker tests passed! Odin's AI Platform is running correctly.${NC}"
        return 0
    else
        echo -e "\n${YELLOW}⚠️  Some tests failed. Check container logs: cd docker && docker compose logs${NC}"
        return 1
    fi
}

# Main function
main() {
    echo -e "${BLUE}Odin's AI Docker Verification Script${NC}"
    echo "============================================="

    test_containers
    test_endpoints
    test_gpu
    test_databases
    test_ai_frameworks
    test_networking

    print_summary
}

# Run main function
main "$@"
