#!/usr/bin/env bash
set -euo pipefail

# Odin AI Status Check Script
# Provides comprehensive status information about the Odin AI system

# shellcheck source=../config/deployment.conf
if [[ -f "$(dirname "$0")/../config/deployment.conf" ]]; then
    source "$(dirname "$0")/../config/deployment.conf"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default values
: "${INSTALL_DIR:=/opt/odins-eye}"
: "${SYSTEM_USER:=odin}"

# Status indicators
STATUS_OK="${GREEN}✓${NC}"
STATUS_WARN="${YELLOW}⚠${NC}"
STATUS_ERROR="${RED}✗${NC}"
STATUS_INFO="${BLUE}ℹ${NC}"

# Print header
print_header() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    Odin AI System Status                    ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
}

# Print section header
print_section() {
    local title="$1"
    echo -e "${PURPLE}${title}${NC}"
    echo -e "${PURPLE}$(printf '%.0s─' {1..50})${NC}"
}

# Check system information
check_system_info() {
    print_section "System Information"

    echo -e "Hostname: ${STATUS_INFO} $(hostname)"
    echo -e "OS: ${STATUS_INFO} $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
    echo -e "Kernel: ${STATUS_INFO} $(uname -r)"
    echo -e "Architecture: ${STATUS_INFO} $(uname -m)"
    echo -e "Uptime: ${STATUS_INFO} $(uptime -p)"
    echo -e "Load Average: ${STATUS_INFO} $(uptime | awk -F'load average:' '{print $2}')"
    echo
}

# Check hardware information
check_hardware_info() {
    print_section "Hardware Information"

    # CPU
    local cpu_cores
    cpu_cores=$(nproc)
    local cpu_model
    cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs)
    echo -e "CPU: ${STATUS_INFO} $cpu_model ($cpu_cores cores)"

    # Memory
    local mem_total
    mem_total=$(free -h | awk '/^Mem:/{print $2}')
    local mem_used
    mem_used=$(free -h | awk '/^Mem:/{print $3}')
    local mem_available
    mem_available=$(free -h | awk '/^Mem:/{print $7}')
    echo -e "Memory: ${STATUS_INFO} $mem_used / $mem_total (Available: $mem_available)"

    # Disk
    local disk_usage
    disk_usage=$(df -h / | awk 'NR==2{print $5}')
    local disk_available
    disk_available=$(df -h / | awk 'NR==2{print $4}')
    echo -e "Disk: ${STATUS_INFO} $disk_usage used (Available: $disk_available)"

    # GPU
    if command -v nvidia-smi >/dev/null 2>&1; then
        local gpu_name
        gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader,nounits | head -1)
        local gpu_memory
        gpu_memory=$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits | head -1)
        echo -e "GPU: ${STATUS_INFO} $gpu_name"
        echo -e "GPU Memory: ${STATUS_INFO} $gpu_memory"
    else
        echo -e "GPU: ${STATUS_ERROR} NVIDIA driver not available"
    fi
    echo
}

# Check service status
check_services() {
    print_section "Service Status"

    local services=(
        "docker:Docker"
        "ssh:SSH"
        "ufw:Firewall"
        "fail2ban:Fail2Ban"
        "nvidia-persistenced:NVIDIA Persistence"
    )

    for service_info in "${services[@]}"; do
        local service_name
        service_name="${service_info%%:*}"
        local display_name
        display_name="${service_info##*:}"

        if systemctl is-active "$service_name" >/dev/null 2>&1; then
            echo -e "$display_name: ${STATUS_OK} Active"
        else
            echo -e "$display_name: ${STATUS_ERROR} Inactive"
        fi
    done
    echo
}

# Check Docker containers
check_docker_containers() {
    print_section "Docker Containers"

    if ! command -v docker >/dev/null 2>&1; then
        echo -e "Docker: ${STATUS_ERROR} Not installed"
        echo
        return
    fi

    if ! systemctl is-active docker >/dev/null 2>&1; then
        echo -e "Docker: ${STATUS_ERROR} Service not running"
        echo
        return
    fi

    local containers
    containers=$(docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}")
    if [[ -n "$containers" ]]; then
        echo "$containers"
    else
        echo -e "${STATUS_WARN} No containers running"
    fi
    echo
}

# Check network status
check_network() {
    print_section "Network Status"

    # Internet connectivity
    if curl -s --max-time 5 https://google.com >/dev/null; then
        echo -e "Internet: ${STATUS_OK} Connected"
    else
        echo -e "Internet: ${STATUS_ERROR} Disconnected"
    fi

    # Local IP
    local local_ip
    local_ip=$(hostname -I | awk '{print $1}')
    echo -e "Local IP: ${STATUS_INFO} $local_ip"

    # Open ports
    echo -e "Open ports:"
    local ports=(22 80 443 8080 3000 3001 3002 5432 6379 9090 9100 8888)
    for port in "${ports[@]}"; do
        if netstat -tlnp 2>/dev/null | grep -q ":$port "; then
            echo -e "  Port $port: ${STATUS_OK} Open"
        else
            echo -e "  Port $port: ${STATUS_WARN} Closed"
        fi
    done
    echo
}

# Check AI/ML environment
check_ai_environment() {
    print_section "AI/ML Environment"

    # Python
    if command -v python3 >/dev/null 2>&1; then
        local python_version
        python_version=$(python3 --version)
        echo -e "Python: ${STATUS_OK} $python_version"
    else
        echo -e "Python: ${STATUS_ERROR} Not installed"
    fi

    # PyTorch
    if python3 -c "import torch" 2>/dev/null; then
        local torch_version
        torch_version=$(python3 -c "import torch; print(torch.__version__)")
        local cuda_available
        cuda_available=$(python3 -c "import torch; print(torch.cuda.is_available())")
        echo -e "PyTorch: ${STATUS_OK} $torch_version"
        if [[ "$cuda_available" == "True" ]]; then
            echo -e "  CUDA: ${STATUS_OK} Available"
        else
            echo -e "  CUDA: ${STATUS_ERROR} Not available"
        fi
    else
        echo -e "PyTorch: ${STATUS_WARN} Not installed"
    fi

    # TensorFlow
    if python3 -c "import tensorflow" 2>/dev/null; then
        local tf_version
        tf_version=$(python3 -c "import tensorflow as tf; print(tf.__version__)")
        echo -e "TensorFlow: ${STATUS_OK} $tf_version"
    else
        echo -e "TensorFlow: ${STATUS_WARN} Not installed"
    fi

    # CUDA
    if command -v nvcc >/dev/null 2>&1; then
        local cuda_version
        cuda_version=$(nvcc --version | grep release | awk '{print $6}')
        echo -e "CUDA Toolkit: ${STATUS_OK} $cuda_version"
    else
        echo -e "CUDA Toolkit: ${STATUS_WARN} Not installed"
    fi
    echo
}

# Check file system
check_filesystem() {
    print_section "File System"

    local dirs=(
        "$INSTALL_DIR:Installation Directory"
        "/var/log/odins-eye:Log Directory"
        "/opt/ai/models:AI Models"
        "/opt/ai/huggingface:HuggingFace Cache"
        "/opt/ai/transformers:Transformers Cache"
        "/opt/ai/datasets:Datasets Cache"
    )

    for dir_info in "${dirs[@]}"; do
        local dir_path
        dir_path="${dir_info%%:*}"
        local dir_name
        dir_name="${dir_info##*:}"

        if [[ -d "$dir_path" ]]; then
            local dir_size
            dir_size=$(du -sh "$dir_path" 2>/dev/null | cut -f1)
            echo -e "$dir_name: ${STATUS_OK} Exists ($dir_size)"
        else
            echo -e "$dir_name: ${STATUS_WARN} Missing"
        fi
    done
    echo
}

# Check performance metrics
check_performance() {
    print_section "Performance Metrics"

    # CPU usage
    local cpu_usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    echo -e "CPU Usage: ${STATUS_INFO} ${cpu_usage}%"

    # Memory usage
    local mem_usage
    mem_usage=$(free | awk '/^Mem:/{printf "%.1f", $3/$2*100}')
    echo -e "Memory Usage: ${STATUS_INFO} ${mem_usage}%"

    # Disk usage
    local disk_usage
    disk_usage=$(df / | awk 'NR==2{print $5}' | sed 's/%//')
    echo -e "Disk Usage: ${STATUS_INFO} ${disk_usage}%"

    # GPU usage (if available)
    if command -v nvidia-smi >/dev/null 2>&1; then
        local gpu_util
        gpu_util=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | head -1)
        local gpu_mem_util
        gpu_mem_util=$(nvidia-smi --query-gpu=utilization.memory --format=csv,noheader,nounits | head -1)
        echo -e "GPU Utilization: ${STATUS_INFO} ${gpu_util}%"
        echo -e "GPU Memory Utilization: ${STATUS_INFO} ${gpu_mem_util}%"
    fi

    # Temperature (if available)
    if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
        local temp
        temp=$(($(cat /sys/class/thermal/thermal_zone0/temp) / 1000))
        echo -e "CPU Temperature: ${STATUS_INFO} ${temp}°C"
    fi
    echo
}

# Check security status
check_security() {
    print_section "Security Status"

    # SSH configuration
    if grep -q "PasswordAuthentication no" /etc/ssh/sshd_config; then
        echo -e "SSH Password Auth: ${STATUS_OK} Disabled"
    else
        echo -e "SSH Password Auth: ${STATUS_WARN} Enabled"
    fi

    if grep -q "PermitRootLogin no" /etc/ssh/sshd_config; then
        echo -e "SSH Root Login: ${STATUS_OK} Disabled"
    else
        echo -e "SSH Root Login: ${STATUS_WARN} Enabled"
    fi

    # Firewall
    if ufw status | grep -q "Status: active"; then
        echo -e "Firewall: ${STATUS_OK} Active"
    else
        echo -e "Firewall: ${STATUS_ERROR} Inactive"
    fi

    # Fail2Ban
    if systemctl is-active fail2ban >/dev/null 2>&1; then
        echo -e "Fail2Ban: ${STATUS_OK} Active"
    else
        echo -e "Fail2Ban: ${STATUS_ERROR} Inactive"
    fi

    # Failed login attempts
    local failed_attempts
    failed_attempts=$(grep "Failed password" /var/log/auth.log | wc -l)
    echo -e "Failed SSH login attempts: $failed_attempts"
    echo
}

# Print summary
print_summary() {
    print_section "System Summary"

    echo -e "System Status: ${STATUS_OK} Operational"
    echo -e "Last Check: $(date)"
    echo -e "Next Check: $(date -d '+5 minutes')"
    echo
    echo -e "${CYAN}For detailed logs, check: /var/log/odins-eye/${NC}"
    echo -e "${CYAN}For configuration, check: $INSTALL_DIR/config/${NC}"
}

# Main function
main() {
    print_header
    check_system_info
    check_hardware_info
    check_services
    check_docker_containers
    check_network
    check_ai_environment
    check_filesystem
    check_performance
    check_security
    print_summary
}

# Run main function
main "$@"
