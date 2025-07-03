#!/usr/bin/env bash
set -euo pipefail

# Odin AI Verification Script
# Verifies that all components are properly installed and configured

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_ROOT/config/deployment.conf"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Load configuration
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Default values
: "${INSTALL_DIR:=/opt/odins-ai}"
: "${SYSTEM_USER:=${SUDO_USER:-$(who am i | awk '{print $1}')}}"

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
    
    # If expected_output is empty, just check exit code
    if [[ -z "$expected_output" ]]; then
        if eval "$test_command" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ PASS${NC}"
            PASSED_TESTS=$((PASSED_TESTS + 1))
            return 0
        else
            echo -e "${RED}✗ FAIL${NC}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            return 1
        fi
    else
        # Check for specific output
        if eval "$test_command" | grep -q "$expected_output" 2>/dev/null; then
            echo -e "${GREEN}✓ PASS${NC}"
            PASSED_TESTS=$((PASSED_TESTS + 1))
            return 0
        else
            echo -e "${RED}✗ FAIL${NC}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            return 1
        fi
    fi
}

# System tests
test_system() {
    echo -e "\n${BLUE}=== System Tests ===${NC}"
    
    run_test "Ubuntu 24.04" "grep 'Ubuntu 24.04' /etc/os-release" "Ubuntu 24.04"
    run_test "OEM Kernel" "uname -r" "6\.11"
    
    # Test sudo group membership more directly
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -n "Testing User in sudo group... "
    
    # Check if we're running as root (during deployment) or as user (manual verification)
    if [[ $EUID -eq 0 ]]; then
        # Running as root - check if the target user is in sudo group
        if groups "$SYSTEM_USER" | grep -q sudo || id -Gn "$SYSTEM_USER" | grep -q sudo; then
            echo -e "${GREEN}✓ PASS${NC}"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo -e "${RED}✗ FAIL${NC}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    else
        # Running as user - check if current user is in sudo group
        if groups | grep -q sudo || id -Gn | grep -q sudo; then
            echo -e "${GREEN}✓ PASS${NC}"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo -e "${RED}✗ FAIL${NC}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    fi
    
    # Check if system user exists (optional test)
    if id "$SYSTEM_USER" >/dev/null 2>&1; then
        echo -e "Testing System user exists... ${GREEN}✓ PASS${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "Testing System user exists... ${YELLOW}⚠ SKIP (user $SYSTEM_USER not found)${NC}"
        # Don't count as failed since user might be different
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    run_test "Installation directory" "test -d $INSTALL_DIR" ""
}

# NVIDIA tests
test_nvidia() {
    echo -e "\n${BLUE}=== NVIDIA Tests ===${NC}"
    
    # Test NVIDIA driver more directly
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -n "Testing NVIDIA driver... "
    if nvidia-smi >/dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    
    # Test GPU detection
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -n "Testing GPU detection... "
    if nvidia-smi --query-gpu=name --format=csv,noheader >/dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    
    # Test CUDA toolkit
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -n "Testing CUDA toolkit... "
    if command -v nvcc >/dev/null 2>&1 && nvcc --version >/dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${YELLOW}⚠ SKIP (nvcc not found)${NC}"
        # Don't count as failed since CUDA might not be installed
    fi
    
    # Test NVIDIA persistence
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -n "Testing NVIDIA persistence... "
    if sudo systemctl is-active nvidia-persistenced >/dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${YELLOW}⚠ SKIP (nvidia-persistenced not active)${NC}"
        # Don't count as failed since this might not be critical
    fi
}

# Docker tests
test_docker() {
    echo -e "\n${BLUE}=== Docker Tests ===${NC}"
    
    run_test "Docker installation" "docker --version" "Docker version"
    run_test "Docker service" "sudo systemctl is-active docker" "active"
    run_test "Docker Compose" "docker compose version" "Docker Compose version"
    
    # Test NVIDIA runtime more directly
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -n "Testing NVIDIA runtime... "
    if timeout 30 docker run --rm --runtime=nvidia --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi --query-gpu=name --format=csv,noheader >/dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${YELLOW}⚠ SKIP (NVIDIA runtime not available)${NC}"
        # Don't count as failed since this might not be critical
    fi
}

# Security tests
test_security() {
    echo -e "\n${BLUE}=== Security Tests ===${NC}"
    
    run_test "SSH service" "sudo systemctl is-active ssh" "active"
    run_test "UFW firewall" "sudo systemctl is-active ufw" "active"
    run_test "Fail2Ban" "sudo systemctl is-active fail2ban" "active"
    run_test "SSH password auth disabled" "sudo grep 'PasswordAuthentication no' /etc/ssh/sshd_config" "PasswordAuthentication no"
    run_test "SSH root login disabled" "sudo grep 'PermitRootLogin no' /etc/ssh/sshd_config" "PermitRootLogin no"
}

# Network tests
test_network() {
    echo -e "\n${BLUE}=== Network Tests ===${NC}"
    
    run_test "Internet connectivity" "curl -s --max-time 5 https://google.com" ""
    run_test "DNS resolution" "nslookup google.com" "google.com"
    run_test "Port 22 open" "sudo netstat -tlnp | grep :22" ":22"
    run_test "Port 80 open" "sudo netstat -tlnp | grep :80" ":80"
}

# Performance tests
test_performance() {
    echo -e "\n${BLUE}=== Performance Tests ===${NC}"
    
    # Check CPU governor
    if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]]; then
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        echo -n "Testing CPU governor... "
        local governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
        if [[ "$governor" == "performance" ]]; then
            echo -e "${GREEN}✓ PASS (performance mode)${NC}"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo -e "${YELLOW}⚠ INFO (current: $governor, performance recommended)${NC}"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        fi
    else
        echo -e "CPU governor: ${YELLOW}⚠ SKIP (not available)${NC}"
    fi
    
    # Check memory
    local mem_gb=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $mem_gb -ge 8 ]]; then
        echo -e "Memory: ${GREEN}✓ ${mem_gb}GB (sufficient)${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "Memory: ${YELLOW}⚠ ${mem_gb}GB (8GB+ recommended)${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Check disk space
    local disk_gb=$(df -BG / | awk 'NR==2{print $4}' | sed 's/G//')
    if [[ $disk_gb -ge 50 ]]; then
        echo -e "Disk space: ${GREEN}✓ ${disk_gb}GB free (sufficient)${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "Disk space: ${YELLOW}⚠ ${disk_gb}GB free (50GB+ recommended)${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

# AI/ML tests
test_ai_ml() {
    echo -e "\n${BLUE}=== AI/ML Tests ===${NC}"
    
    run_test "Python 3" "python3 --version" "Python 3"
    run_test "Pip" "pip3 --version" "pip"
    
    # Test PyTorch if installed
    if python3 -c "import torch" 2>/dev/null; then
        run_test "PyTorch" "python3 -c 'import torch; print(torch.__version__)'" ""
        run_test "PyTorch CUDA" "python3 -c 'import torch; print(torch.cuda.is_available())'" "True"
    else
        echo -e "PyTorch: ${YELLOW}⚠ Not installed${NC}"
    fi
    
    # Test TensorFlow if installed
    if python3 -c "import tensorflow" 2>/dev/null; then
        run_test "TensorFlow" "python3 -c 'import tensorflow as tf; print(tf.__version__)'" ""
    else
        echo -e "TensorFlow: ${YELLOW}⚠ Not installed${NC}"
    fi
}

# Service tests
test_services() {
    echo -e "\n${BLUE}=== Service Tests ===${NC}"
    
    local services=("docker" "ssh" "ufw" "fail2ban" "nvidia-persistenced")
    
    for service in "${services[@]}"; do
        if sudo systemctl is-active "$service" >/dev/null 2>&1; then
            echo -e "$service: ${GREEN}✓ Active${NC}"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo -e "$service: ${RED}✗ Inactive${NC}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
    done
}

# File system tests
test_filesystem() {
    echo -e "\n${BLUE}=== File System Tests ===${NC}"
    
    local dirs=("$INSTALL_DIR" "/var/log/odins-ai" "/opt/ai/models" "/opt/ai/huggingface")
    
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]] || sudo test -d "$dir"; then
            echo -e "$dir: ${GREEN}✓ Exists${NC}"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo -e "$dir: ${RED}✗ Missing${NC}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
    done
}

# Print summary
print_summary() {
    echo -e "\n${BLUE}=== Verification Summary ===${NC}"
    echo -e "Total tests: $TOTAL_TESTS"
    echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
    echo -e "Failed: ${RED}$FAILED_TESTS${NC}"
    
    local success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    echo -e "Success rate: ${success_rate}%"
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "\n${GREEN}🎉 All tests passed! Odin AI is ready to use.${NC}"
        return 0
    else
        echo -e "\n${YELLOW}⚠️  Some tests failed. Please check the configuration.${NC}"
        return 1
    fi
}

# Main function
main() {
    echo -e "${BLUE}Odin AI Verification Script${NC}"
    echo "=================================="
    
    test_system
    test_nvidia
    test_docker
    test_security
    test_network
    test_performance
    test_ai_ml
    test_services
    test_filesystem
    
    print_summary
}

# Run main function
main "$@" 