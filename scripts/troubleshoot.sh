#!/usr/bin/env bash
set -euo pipefail

# Odin AI Troubleshooting Script
# Diagnoses and fixes common issues with the Odin AI system

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_ROOT/config/deployment.conf"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Load configuration
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Default values
: "${INSTALL_DIR:=/opt/odins-ai}"
: "${SYSTEM_USER:=odin}"

# Status indicators
STATUS_OK="${GREEN}✓${NC}"
STATUS_WARN="${YELLOW}⚠${NC}"
STATUS_ERROR="${RED}✗${NC}"
STATUS_INFO="${BLUE}ℹ${NC}"

# Print header
print_header() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                  Odin AI Troubleshooting                    ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
}

# Print section header
print_section() {
    local title="$1"
    echo -e "${PURPLE}${title}${NC}"
    echo -e "${PURPLE}$(printf '%.0s─' {1..50})${NC}"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}❌ This script requires root privileges${NC}"
        echo -e "Please run: sudo $0"
        exit 1
    fi
}

# GPU troubleshooting
troubleshoot_gpu() {
    print_section "GPU Troubleshooting"

    echo -e "Checking NVIDIA drivers..."

    # Check if NVIDIA GPU is present
    if ! lspci | grep -i nvidia >/dev/null; then
        echo -e "  ${STATUS_ERROR} No NVIDIA GPU detected"
        return 1
    fi

    # Check if driver is loaded
    if ! lsmod | grep nvidia >/dev/null; then
        echo -e "  ${STATUS_ERROR} NVIDIA driver not loaded"
        echo -e "  ${STATUS_INFO} Attempting to load driver..."

        # Try to load the driver
        modprobe nvidia 2>/dev/null || {
            echo -e "  ${STATUS_ERROR} Failed to load NVIDIA driver"
            echo -e "  ${STATUS_INFO} Reinstalling NVIDIA driver..."
            apt update
            apt install --reinstall nvidia-driver-575-open
            echo -e "  ${STATUS_INFO} Please reboot and try again"
            return 1
        }
    fi

    # Check nvidia-smi
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        echo -e "  ${STATUS_ERROR} nvidia-smi not found"
        echo -e "  ${STATUS_INFO} Installing NVIDIA utilities..."
        apt install nvidia-utils-575
    fi

    # Test nvidia-smi
    if nvidia-smi >/dev/null 2>&1; then
        echo -e "  ${STATUS_OK} NVIDIA driver working"
        nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader,nounits
    else
        echo -e "  ${STATUS_ERROR} nvidia-smi failed"
        return 1
    fi

    echo
}

# Docker troubleshooting
troubleshoot_docker() {
    print_section "Docker Troubleshooting"

    # Check if Docker is installed
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "  ${STATUS_ERROR} Docker not installed"
        echo -e "  ${STATUS_INFO} Installing Docker..."
        curl -fsSL https://get.docker.com | sh
        usermod -aG docker "$SYSTEM_USER"
        systemctl enable --now docker
    fi

    # Check Docker service
    if ! systemctl is-active docker >/dev/null 2>&1; then
        echo -e "  ${STATUS_ERROR} Docker service not running"
        echo -e "  ${STATUS_INFO} Starting Docker service..."
        systemctl start docker
    fi

    # Check Docker daemon
    if ! docker info >/dev/null 2>&1; then
        echo -e "  ${STATUS_ERROR} Docker daemon not responding"
        echo -e "  ${STATUS_INFO} Restarting Docker..."
        systemctl restart docker
    fi

    # Check NVIDIA Container Toolkit
    if ! docker run --rm --runtime=nvidia --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi >/dev/null 2>&1; then
        echo -e "  ${STATUS_ERROR} NVIDIA Container Toolkit not working"
        echo -e "  ${STATUS_INFO} Reinstalling NVIDIA Container Toolkit..."

        # Reinstall NVIDIA Container Toolkit
        apt update
        apt install --reinstall nvidia-container-toolkit
        systemctl restart docker

        # Test again
        if docker run --rm --runtime=nvidia --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi >/dev/null 2>&1; then
            echo -e "  ${STATUS_OK} NVIDIA Container Toolkit fixed"
        else
            echo -e "  ${STATUS_ERROR} Failed to fix NVIDIA Container Toolkit"
            return 1
        fi
    else
        echo -e "  ${STATUS_OK} Docker and NVIDIA Container Toolkit working"
    fi

    echo
}

# Service troubleshooting
troubleshoot_services() {
    print_section "Service Troubleshooting"

    local services=("docker" "ssh" "ufw" "fail2ban" "nvidia-persistenced")

    for service in "${services[@]}"; do
        if systemctl is-active "$service" >/dev/null 2>&1; then
            echo -e "  $service: ${STATUS_OK} Active"
        else
            echo -e "  $service: ${STATUS_ERROR} Inactive"
            echo -e "    ${STATUS_INFO} Starting $service..."
            systemctl start "$service" 2>/dev/null || {
                echo -e "    ${STATUS_ERROR} Failed to start $service"
                systemctl status "$service" --no-pager -l
            }
        fi
    done

    echo
}

# Permission troubleshooting
troubleshoot_permissions() {
    print_section "Permission Troubleshooting"

    # Check user exists
    if ! id "$SYSTEM_USER" >/dev/null 2>&1; then
        echo -e "  ${STATUS_ERROR} User $SYSTEM_USER does not exist"
        echo -e "  ${STATUS_INFO} Creating user $SYSTEM_USER..."
        useradd -m -s /bin/bash "$SYSTEM_USER"
    fi

    # Check directories and permissions
    local dirs=("$INSTALL_DIR" "/var/log/odins-ai" "/opt/ai/models" "/opt/ai/huggingface")

    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            echo -e "  ${STATUS_WARN} Directory $dir does not exist"
            echo -e "    ${STATUS_INFO} Creating directory..."
            mkdir -p "$dir"
        fi

        # Check ownership
        local owner=$(stat -c '%U' "$dir" 2>/dev/null || echo "unknown")
        if [[ "$owner" != "$SYSTEM_USER" ]]; then
            echo -e "  ${STATUS_WARN} Wrong ownership for $dir (owner: $owner)"
            echo -e "    ${STATUS_INFO} Fixing ownership..."
            chown -R "$SYSTEM_USER:$SYSTEM_USER" "$dir"
        fi
    done

    # Check Docker group membership
    if ! groups "$SYSTEM_USER" | grep -q docker; then
        echo -e "  ${STATUS_WARN} User $SYSTEM_USER not in docker group"
        echo -e "    ${STATUS_INFO} Adding to docker group..."
        usermod -aG docker "$SYSTEM_USER"
    fi

    echo -e "  ${STATUS_OK} Permissions fixed"
    echo
}

# Network troubleshooting
troubleshoot_networking() {
    print_section "Network Troubleshooting"

    log "INFO" "Starting network troubleshooting..."
    echo -e "${BLUE}🔍 Troubleshooting network configuration...${NC}"

    # Check current network status
    echo -e "${YELLOW}📊 Current Network Status:${NC}"
    ip addr show | grep -E "^[0-9]+:|inet " | head -20

    echo
    echo -e "${YELLOW}🌐 Network Interfaces:${NC}"
    ip link show | grep -E "^[0-9]+:"

    echo
    echo -e "${YELLOW}🛣️  Routing Table:${NC}"
    ip route show | head -10

    # Check if we have any IP address
    local ip_address=$(hostname -I | awk '{print $1}')
    if [[ -n "$ip_address" && "$ip_address" != "127.0.0.1" ]]; then
        echo -e "${GREEN}✅ System has IP address: $ip_address${NC}"

        # Find which interface has the IP
        local active_interface=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'dev \K\S+' | head -1)
        if [[ -n "$active_interface" ]]; then
            echo -e "${GREEN}✅ Active interface: $active_interface${NC}"
        fi
    else
        echo -e "${RED}❌ No IP address assigned${NC}"
    fi

    # Check Netplan configuration
    echo
    echo -e "${YELLOW}📋 Netplan Configuration:${NC}"
    if [[ -d "/etc/netplan" ]]; then
        ls -la /etc/netplan/
        echo
        for file in /etc/netplan/*.yaml; do
            if [[ -f "$file" ]]; then
                echo -e "${BLUE}📄 $file:${NC}"
                cat "$file"
                echo
            fi
        done
    else
        echo -e "${RED}❌ No Netplan configuration directory found${NC}"
    fi

    # Check if specific interfaces exist
    echo -e "${YELLOW}🔍 Interface Detection:${NC}"
    for interface in enp7s0 enp6s0 enp5s0 enp4s0 enp3s0 enp2s0 enp1s0 enp0s0; do
        if ip link show "$interface" >/dev/null 2>&1; then
            local status=$(ip link show "$interface" | grep -o "state [A-Z]*" | cut -d' ' -f2)
            local has_ip=""
            if ip addr show "$interface" | grep -q "inet "; then
                has_ip=" (has IP)"
            fi
            echo -e "${GREEN}✅ $interface: $status$has_ip${NC}"
        else
            echo -e "${RED}❌ $interface: not found${NC}"
        fi
    done

    # Check for other ethernet interfaces
    echo
    echo -e "${YELLOW}🔍 Other Ethernet Interfaces:${NC}"
    ip link show | grep -E "^[0-9]+: en" | while read line; do
        local interface=$(echo "$line" | cut -d: -f2 | xargs)
        local status=$(echo "$line" | grep -o "state [A-Z]*" | cut -d' ' -f2)
        local has_ip=""
        if ip addr show "$interface" | grep -q "inet "; then
            has_ip=" (has IP)"
        fi
        echo -e "${BLUE}📡 $interface: $status$has_ip${NC}"
    done

    # Test internet connectivity
    echo
    echo -e "${YELLOW}🌍 Internet Connectivity Test:${NC}"
    if curl -s --max-time 10 https://google.com >/dev/null; then
        echo -e "${GREEN}✅ Internet connectivity working${NC}"
    else
        echo -e "${RED}❌ No internet connectivity${NC}"

        # Try DNS resolution
        if nslookup google.com >/dev/null 2>&1; then
            echo -e "${YELLOW}⚠️  DNS resolution working but no internet access${NC}"
        else
            echo -e "${RED}❌ DNS resolution failed${NC}"
        fi
    fi

    # Check DHCP status
    echo
    echo -e "${YELLOW}🔌 DHCP Status:${NC}"
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet systemd-networkd; then
            echo -e "${GREEN}✅ systemd-networkd is running${NC}"
        else
            echo -e "${RED}❌ systemd-networkd is not running${NC}"
        fi

        if systemctl is-active --quiet NetworkManager; then
            echo -e "${GREEN}✅ NetworkManager is running${NC}"
        else
            echo -e "${YELLOW}⚠️  NetworkManager is not running${NC}"
        fi
    fi

    # Provide recommendations
    echo
    echo -e "${YELLOW}💡 Recommendations:${NC}"

    if [[ -z "$ip_address" || "$ip_address" == "127.0.0.1" ]]; then
        echo -e "${BLUE}1. No IP address detected. Try:${NC}"
        echo "   sudo netplan apply"
        echo "   sudo systemctl restart systemd-networkd"
        echo
        echo -e "${BLUE}2. If using a different interface (like enx6c1ff721c6a0), create config:${NC}"
        echo "   sudo nano /etc/netplan/01-ethernet.yaml"
        echo "   # Add configuration for your specific interface"
        echo
    else
        echo -e "${GREEN}✅ Network appears to be working with IP: $ip_address${NC}"
        echo -e "${BLUE}If you need to configure a specific interface, check the Netplan files above.${NC}"
    fi

    echo
}

# AI/ML environment troubleshooting
troubleshoot_ai_ml() {
    print_section "AI/ML Environment Troubleshooting"

    # Check Python
    if ! command -v python3 >/dev/null 2>&1; then
        echo -e "  ${STATUS_ERROR} Python 3 not installed"
        echo -e "    ${STATUS_INFO} Installing Python 3..."
        apt update
        apt install python3 python3-pip python3-venv
    else
        echo -e "  ${STATUS_OK} Python 3 installed"
    fi

    # Check PyTorch
    if python3 -c "import torch" 2>/dev/null; then
        local torch_version=$(python3 -c "import torch; print(torch.__version__)")
        local cuda_available=$(python3 -c "import torch; print(torch.cuda.is_available())")
        echo -e "  ${STATUS_OK} PyTorch $torch_version"
        if [[ "$cuda_available" == "True" ]]; then
            echo -e "    ${STATUS_OK} CUDA available"
        else
            echo -e "    ${STATUS_ERROR} CUDA not available"
        fi
    else
        echo -e "  ${STATUS_WARN} PyTorch not installed"
        echo -e "    ${STATUS_INFO} Install with: pip3 install torch torchvision torchaudio"
    fi

    # Check CUDA toolkit
    if command -v nvcc >/dev/null 2>&1; then
        local cuda_version=$(nvcc --version | grep release | awk '{print $6}')
        echo -e "  ${STATUS_OK} CUDA Toolkit $cuda_version"
    else
        echo -e "  ${STATUS_WARN} CUDA Toolkit not installed"
        echo -e "    ${STATUS_INFO} Install with: apt install cuda-toolkit-12-9"
    fi

    echo
}

# Performance troubleshooting
troubleshoot_performance() {
    print_section "Performance Troubleshooting"

    # Check CPU governor
    if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]]; then
        local governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
        if [[ "$governor" == "performance" ]]; then
            echo -e "  ${STATUS_OK} CPU governor: $governor"
        else
            echo -e "  ${STATUS_WARN} CPU governor: $governor (performance recommended)"
            echo -e "    ${STATUS_INFO} Set to performance: echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"
        fi
    fi

    # Check memory
    local mem_gb=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $mem_gb -lt 8 ]]; then
        echo -e "  ${STATUS_WARN} Low memory: ${mem_gb}GB (8GB+ recommended)"
    else
        echo -e "  ${STATUS_OK} Memory: ${mem_gb}GB"
    fi

    # Check disk space
    local disk_gb=$(df -BG / | awk 'NR==2{print $4}' | sed 's/G//')
    if [[ $disk_gb -lt 50 ]]; then
        echo -e "  ${STATUS_WARN} Low disk space: ${disk_gb}GB (50GB+ recommended)"
    else
        echo -e "  ${STATUS_OK} Disk space: ${disk_gb}GB available"
    fi

    # Check GPU temperature
    if command -v nvidia-smi >/dev/null 2>&1; then
        local gpu_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits | head -1)
        if [[ $gpu_temp -gt 80 ]]; then
            echo -e "  ${STATUS_WARN} High GPU temperature: ${gpu_temp}°C"
        else
            echo -e "  ${STATUS_OK} GPU temperature: ${gpu_temp}°C"
        fi
    fi

    echo
}

# Log analysis
analyze_logs() {
    print_section "Log Analysis"

    # Check deployment log
    if [[ -f /var/log/odins-ai-deployment.log ]]; then
        echo -e "  ${STATUS_INFO} Deployment log found"
        echo -e "    Last 10 lines:"
        tail -10 /var/log/odins-ai-deployment.log | sed 's/^/      /'
    else
        echo -e "  ${STATUS_WARN} Deployment log not found"
    fi

    # Check system logs for errors
    echo -e "  ${STATUS_INFO} Recent system errors:"
    journalctl --since "1 hour ago" -p err --no-pager | tail -5 | sed 's/^/    /' || echo "    No recent errors"

    # Check Docker logs
    if command -v docker >/dev/null 2>&1; then
        echo -e "  ${STATUS_INFO} Recent Docker errors:"
        docker logs --tail 10 $(docker ps -q) 2>&1 | grep -i error | tail -5 | sed 's/^/    /' || echo "    No recent Docker errors"
    fi

    echo
}

# Fix common issues
fix_common_issues() {
    print_section "Fixing Common Issues"

    # Update system
    echo -e "  ${STATUS_INFO} Updating system packages..."
    apt update && apt upgrade -y

    # Clean up Docker
    echo -e "  ${STATUS_INFO} Cleaning up Docker..."
    docker system prune -f 2>/dev/null || true

    # Restart services
    echo -e "  ${STATUS_INFO} Restarting services..."
    systemctl restart docker ssh ufw fail2ban nvidia-persistenced 2>/dev/null || true

    # Fix permissions
    echo -e "  ${STATUS_INFO} Fixing permissions..."
    chown -R "$SYSTEM_USER:$SYSTEM_USER" "$INSTALL_DIR" /opt/ai /var/log/odins-ai 2>/dev/null || true

    echo -e "  ${STATUS_OK} Common fixes applied"
    echo
}

# Print summary
print_summary() {
    print_section "Troubleshooting Summary"

    echo -e "Troubleshooting completed at: $(date)"
    echo
    echo -e "${CYAN}Next steps:${NC}"
    echo -e "1. Run verification: ./scripts/verify.sh"
    echo -e "2. Check status: ./scripts/status.sh"
    echo -e "3. Test GPU: nvidia-smi"
    echo -e "4. Test Docker: docker run --rm --runtime=nvidia --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi"
    echo
    echo -e "${CYAN}If issues persist:${NC}"
    echo -e "1. Check logs: tail -f /var/log/odins-ai-deployment.log"
    echo -e "2. Reboot system: sudo reboot"
    echo -e "3. Reinstall: sudo ./scripts/deploy.sh"
    echo
}

# Main function
main() {
    check_root
    print_header

    local fix_mode=false

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --fix)
                fix_mode=true
                shift
                ;;
            --gpu)
                troubleshoot_gpu
                exit 0
                ;;
            --docker)
                troubleshoot_docker
                exit 0
                ;;
            --services)
                troubleshoot_services
                exit 0
                ;;
            --permissions)
                troubleshoot_permissions
                exit 0
                ;;
            --network)
                troubleshoot_networking
                exit 0
                ;;
            --ai-ml)
                troubleshoot_ai_ml
                exit 0
                ;;
            --performance)
                troubleshoot_performance
                exit 0
                ;;
            --logs)
                analyze_logs
                exit 0
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --fix           Apply automatic fixes"
                echo "  --gpu           Troubleshoot GPU issues only"
                echo "  --docker        Troubleshoot Docker issues only"
                echo "  --services      Troubleshoot services only"
                echo "  --permissions   Troubleshoot permissions only"
                echo "  --network       Troubleshoot network issues only"
                echo "  --ai-ml         Troubleshoot AI/ML environment only"
                echo "  --performance   Troubleshoot performance only"
                echo "  --logs          Analyze logs only"
                echo "  -h, --help      Show this help"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # Run all troubleshooting
    troubleshoot_gpu
    troubleshoot_docker
    troubleshoot_services
    troubleshoot_permissions
    troubleshoot_networking
    troubleshoot_ai_ml
    troubleshoot_performance
    analyze_logs

    if [[ "$fix_mode" == "true" ]]; then
        fix_common_issues
    fi

    print_summary
}

# Run main function
main "$@"
