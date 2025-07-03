#!/usr/bin/env bash
set -euo pipefail

# Odin's AI Complete Verification Test Runner
# Runs all verification scripts in optimal order

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Test results tracking
declare -A TEST_RESULTS
declare -A TEST_DURATIONS
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Logging function
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[${timestamp}] [${level}] ${message}"
}

# Print header
print_header() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              🧪 Odin's AI Verification Test Suite           ║${NC}"
    echo -e "${CYAN}║              Complete Docker Deployment Verification        ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
}

# Print section header
print_section() {
    local title="$1"
    echo -e "${PURPLE}${title}${NC}"
    echo -e "${PURPLE}$(printf '%.0s─' {1..60})${NC}"
}

# Run a verification script
run_verification() {
    local script_name="$1"
    local script_path="$2"
    local description="$3"
    local working_dir="${4:-}"  # Optional working directory

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    echo -e "${BLUE}🔄 Running: ${script_name}${NC}"
    echo -e "${YELLOW}   ${description}${NC}"
    echo

    # Check if script exists
    if [[ ! -f "$script_path" ]]; then
        echo -e "${RED}❌ Script not found: ${script_path}${NC}"
        TEST_RESULTS["$script_name"]="FAILED"
        TEST_DURATIONS["$script_name"]="0"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi

    # Make script executable
    chmod +x "$script_path"

    # Run script directly without output capture
    local start_time
    start_time=$(date +%s)

    # Change to working directory if specified
    local original_dir
    original_dir=$(pwd)
    if [[ -n "$working_dir" ]]; then
        cd "$working_dir"
    fi

    if bash "$script_path"; then
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))

        echo -e "${GREEN}✅ ${script_name} completed successfully (${duration}s)${NC}"
        TEST_RESULTS["$script_name"]="PASSED"
        TEST_DURATIONS["$script_name"]="$duration"
        PASSED_TESTS=$((PASSED_TESTS + 1))

        # Return to original directory
        cd "$original_dir"
        return 0
    else
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))

        echo -e "${RED}❌ ${script_name} failed (${duration}s)${NC}"
        TEST_RESULTS["$script_name"]="FAILED"
        TEST_DURATIONS["$script_name"]="$duration"
        FAILED_TESTS=$((FAILED_TESTS + 1))

        # Return to original directory
        cd "$original_dir"
        return 1
    fi
}

# Check prerequisites
check_prerequisites() {
    echo -e "${BLUE}🔍 Checking prerequisites...${NC}"

    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        echo -e "${RED}❌ Docker is not running${NC}"
        echo -e "${YELLOW}💡 Please start Docker first: sudo systemctl start docker${NC}"
        exit 1
    fi

    # Check if we're in the project root
    if [[ ! -f "$PROJECT_ROOT/docker/docker-compose.yml" ]]; then
        echo -e "${RED}❌ Not in project root or docker-compose.yml not found${NC}"
        exit 1
    fi

    echo -e "${GREEN}✅ Prerequisites check passed${NC}"
    echo
}

# Run all verifications
run_all_verifications() {
    print_section "Phase 1: Basic Docker Health Check"
    run_verification "verify-docker.sh" "$SCRIPT_DIR/verify-docker.sh" \
        "Comprehensive Docker container and service verification"

    echo
    print_section "Phase 2: Service Health Verification"
    run_verification "verify-services.sh" "$SCRIPT_DIR/verify-services.sh" \
        "Web service endpoints and database connectivity check" "$PROJECT_ROOT/docker"

    echo
    print_section "Phase 3: Quick GPU Verification"
    run_verification "verify-ai-gpu.sh" "$SCRIPT_DIR/verify-ai-gpu.sh" \
        "Basic GPU access test in main app and Jupyter containers"

    echo
    print_section "Phase 4: Advanced Jupyter GPU Tests"
    run_verification "verify-jupyter.sh" "$SCRIPT_DIR/verify-jupyter.sh" \
        "Comprehensive GPU computation and neural network training tests"
}

# Print detailed results
print_detailed_results() {
    echo
    print_section "Detailed Test Results"

    local max_name_length=0
    for script_name in "${!TEST_RESULTS[@]}"; do
        if [[ ${#script_name} -gt $max_name_length ]]; then
            max_name_length=${#script_name}
        fi
    done

    printf "%-${max_name_length}s | %-8s | %-8s | %s\n" "Test" "Status" "Duration" "Description"
    printf "%-${max_name_length}s-|-%-8s-|-%-8s-|-%s\n" "$(printf '%.0s-' $(seq 1 $max_name_length))" "--------" "--------" "$(printf '%.0s-' $(seq 1 50))"

    for script_name in "${!TEST_RESULTS[@]}"; do
        local status="${TEST_RESULTS[$script_name]}"
        local duration="${TEST_DURATIONS[$script_name]}s"
        local description=""

        case "$script_name" in
            "verify-docker.sh")
                description="Docker container and service verification"
                ;;
            "verify-services.sh")
                description="Web service endpoints and database connectivity"
                ;;
            "verify-ai-gpu.sh")
                description="Basic GPU access test in containers"
                ;;
            "verify-jupyter.sh")
                description="Advanced GPU computation and neural network tests"
                ;;
            *)
                description="Verification test"
                ;;
        esac

        if [[ "$status" == "PASSED" ]]; then
            printf "%-${max_name_length}s | ${GREEN}%-8s${NC} | %-8s | %s\n" "$script_name" "$status" "$duration" "$description"
        else
            printf "%-${max_name_length}s | ${RED}%-8s${NC} | %-8s | %s\n" "$script_name" "$status" "$duration" "$description"
        fi
    done
}

# Print summary
print_summary() {
    echo
    print_section "Test Suite Summary"

    local success_rate=0
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    fi

    echo -e "Total tests run: ${BLUE}${TOTAL_TESTS}${NC}"
    echo -e "Tests passed:    ${GREEN}${PASSED_TESTS}${NC}"
    echo -e "Tests failed:    ${RED}${FAILED_TESTS}${NC}"
    echo -e "Success rate:    ${YELLOW}${success_rate}%${NC}"

    # Calculate total duration
    local total_duration=0
    for duration in "${TEST_DURATIONS[@]}"; do
        total_duration=$((total_duration + duration))
    done
    echo -e "Total duration:  ${BLUE}${total_duration}s${NC}"

    echo
    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "${GREEN}🎉 All verification tests passed! Odin's AI Platform is running correctly.${NC}"
        echo -e "${CYAN}💡 Your Docker deployment is healthy and ready for use.${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️  Some tests failed. Check the output above for details.${NC}"
        echo -e "${YELLOW}💡 Failed tests may indicate issues with:${NC}"
        echo -e "   • Container health"
        echo -e "   • Service connectivity"
        echo -e "   • GPU access"
        echo -e "   • Database connections"
        echo -e "${BLUE}🔧 Run individual tests for more detailed debugging:${NC}"
        echo -e "   • ./scripts/verify-docker.sh"
        echo -e "   • ./scripts/verify-services.sh"
        echo -e "   • ./scripts/verify-ai-gpu.sh"
        echo -e "   • ./scripts/verify-jupyter.sh"
        return 1
    fi
}

# Show service URLs
show_service_urls() {
    echo
    print_section "Service Access URLs"
    echo -e "${CYAN}Main Dashboard:${NC} http://localhost:8080"
    echo -e "${CYAN}Grafana:${NC}        http://localhost:3001 (admin/admin)"
    echo -e "${CYAN}Jupyter Lab:${NC}    http://localhost:8888"
    echo -e "${CYAN}Prometheus:${NC}     http://localhost:9090"
    echo -e "${CYAN}Node Exporter:${NC}  http://localhost:9100"
}

# Main function
main() {
    print_header

    # Check prerequisites
    check_prerequisites

    # Run all verifications
    run_all_verifications

    # Print results
    print_detailed_results
    print_summary
    show_service_urls

    # Exit with appropriate code
    if [[ $FAILED_TESTS -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

# Handle script interruption
trap 'echo -e "\n${YELLOW}⚠️  Test suite interrupted by user${NC}"; exit 130' INT

# Run main function
main "$@"
