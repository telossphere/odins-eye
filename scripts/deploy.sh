#!/usr/bin/env bash
set -euo pipefail

# Set non-interactive mode for all package installations
export DEBIAN_FRONTEND=noninteractive

# ──────────────────────────────────────────────────────────────
# Odin AI Ubuntu 24.04 One-Click Setup Script ©2025
# Enhanced version with logging, error handling, and modularity
# ──────────────────────────────────────────────────────────────

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="/var/log/odins-ai-deployment.log"
CONFIG_FILE="$PROJECT_ROOT/config/deployment.conf"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR" "Script failed at line $1"
    log "ERROR" "Command: $2"
    exit 1
}

trap 'error_exit ${LINENO} "$BASH_COMMAND"' ERR

# Load configuration if exists
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Default configuration
: "${INSTALL_NATIVE_CUDA:=yes}"
: "${TIMEZONE:=America/New_York}"
: "${SYSTEM_USER:=${SUDO_USER:-$(who am i | awk '{print $1}')}}"
: "${INSTALL_DIR:=/opt/odins-ai}"
: "${SKIP_REBOOT:=false}"

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}❌ Please run as root: sudo $0${NC}" >&2
        exit 1
    fi
}

# Function to check system requirements
check_system() {
    log "INFO" "Checking system requirements..."

    # Check Ubuntu version
    if ! grep -q "Ubuntu 24.04" /etc/os-release; then
        log "WARN" "This script is designed for Ubuntu 24.04. Current system: $(grep PRETTY_NAME /etc/os-release)"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    fi

    # Check available memory
    local mem_gb=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $mem_gb -lt 8 ]]; then
        log "WARN" "System has only ${mem_gb}GB RAM. 8GB+ recommended for AI workloads."
    fi

    # Check available disk space
    local disk_gb=$(df -BG / | awk 'NR==2{print $4}' | sed 's/G//')
    if [[ $disk_gb -lt 50 ]]; then
        log "WARN" "System has only ${disk_gb}GB free space. 50GB+ recommended."
    fi

    log "INFO" "System requirements check completed"
}

# Function to update base system
update_system() {
    log "INFO" "Updating base system..."

    apt update

    # Only upgrade if there are packages to upgrade
    if apt list --upgradable 2>/dev/null | grep -q upgradable; then
        apt upgrade -y
        log "INFO" "System packages upgraded"
    else
        log "INFO" "No packages to upgrade"
    fi

    # Install essential packages (only if not already installed)
    local essential_packages=(
        curl wget git gnupg ca-certificates unzip lsb-release
        build-essential dkms htop neofetch tmux net-tools pciutils
        software-properties-common apt-transport-https
    )

    local packages_to_install=()
    for package in "${essential_packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            packages_to_install+=("$package")
        fi
    done

    if [[ ${#packages_to_install[@]} -gt 0 ]]; then
        apt install -y "${packages_to_install[@]}"
        log "INFO" "Essential packages installed: ${packages_to_install[*]}"
    else
        log "INFO" "All essential packages already installed"
    fi

    log "INFO" "Base system updated successfully"
}

# Function to configure time and NTP
configure_time() {
    log "INFO" "Configuring timezone and NTP..."

    timedatectl set-timezone "$TIMEZONE"
    timedatectl set-ntp true

    log "INFO" "Time configuration completed"
}

# Function to install OEM kernel
install_oem_kernel() {
    log "INFO" "Checking kernel version..."

    if ! uname -r | grep -q '6\.11'; then
        log "INFO" "Installing OEM kernel..."
        apt install -y linux-oem-24.04 linux-oem-24.04b

        if [[ "$SKIP_REBOOT" != "true" ]]; then
            log "INFO" "Rebooting to load the OEM kernel..."
            reboot
            exit 0
        else
            log "WARN" "Skipping reboot. Please reboot manually to load OEM kernel."
        fi
    else
        log "INFO" "OEM kernel already installed"
    fi
}

# Function to configure networking
configure_networking() {
    log "INFO" "Configuring network interfaces..."

    # Check if we're running after OEM kernel reboot
    if uname -r | grep -q '6\.11'; then
        log "INFO" "OEM kernel detected, configuring network interfaces..."

        # Find the active network interface that has an IP address
        local active_interface=""
        local primary_interface=""

        # First, check if any interface already has an IP
        active_interface=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'dev \K\S+' | head -1)
        if [[ -n "$active_interface" ]]; then
            log "INFO" "Found active interface with IP: $active_interface"
            echo -e "${GREEN}✅ Network already configured: $active_interface${NC}"
            return 0
        fi

        # If no active interface, find the primary ethernet interface
        # Check for common interface names in order of preference
        for interface in enp7s0 enp6s0 enp5s0 enp4s0 enp3s0 enp2s0 enp1s0 enp0s0; do
            if ip link show "$interface" >/dev/null 2>&1; then
                primary_interface="$interface"
                log "INFO" "Found primary interface: $primary_interface"
                break
            fi
        done

        # If no specific interface found, use the first ethernet interface
        if [[ -z "$primary_interface" ]]; then
            primary_interface=$(ip link show | grep -E '^[0-9]+: en' | head -1 | cut -d: -f2 | xargs)
            if [[ -n "$primary_interface" ]]; then
                log "INFO" "Using first available ethernet interface: $primary_interface"
            else
                log "WARN" "No ethernet interface found, skipping network configuration"
                return 0
            fi
        fi

        # Check if the interface is already configured
        if ip addr show "$primary_interface" | grep -q "inet "; then
            log "INFO" "Interface $primary_interface already has an IP address"
            echo -e "${GREEN}✅ Interface $primary_interface already configured${NC}"
            return 0
        fi

        # Create Netplan configuration
        local netplan_file="/etc/netplan/01-${primary_interface}.yaml"

        log "INFO" "Creating Netplan configuration for $primary_interface..."

        cat > "$netplan_file" <<EOF
network:
  version: 2
  ethernets:
    $primary_interface:
      dhcp4: true
      dhcp6: true
      optional: true
EOF

        # Set proper permissions (Netplan requires root-only access)
        chmod 600 "$netplan_file"

        # Apply the Netplan configuration
        log "INFO" "Applying Netplan configuration..."
        if netplan apply; then
            log "INFO" "Netplan configuration applied successfully"

            # Wait a moment for DHCP to get an IP
            log "INFO" "Waiting for DHCP to assign IP address..."
            sleep 10

            # Check if we got an IP address
            local ip_address
            ip_address=$(ip addr show "$primary_interface" | grep -oP 'inet \K\S+' | head -1)
            if [[ -n "$ip_address" ]]; then
                log "INFO" "Network configured successfully. IP address: $ip_address"
                echo -e "${GREEN}✅ Network configured: $primary_interface -> $ip_address${NC}"
            else
                log "WARN" "No IP address assigned yet. DHCP may still be negotiating."
                echo -e "${YELLOW}⚠️  Network configured but no IP yet. DHCP in progress...${NC}"

                # Check if any interface got an IP (in case DHCP assigned to a different interface)
                local any_ip=$(hostname -I | awk '{print $1}')
                if [[ -n "$any_ip" && "$any_ip" != "127.0.0.1" ]]; then
                    log "INFO" "Found IP address on different interface: $any_ip"
                    echo -e "${GREEN}✅ Network working: IP address $any_ip assigned${NC}"
                fi
            fi
        else
            log "ERROR" "Failed to apply Netplan configuration"
            echo -e "${RED}❌ Failed to apply network configuration${NC}"
            return 1
        fi

        # Test internet connectivity
        log "INFO" "Testing internet connectivity..."
        if curl -s --max-time 10 https://google.com >/dev/null; then
            log "INFO" "Internet connectivity confirmed"
            echo -e "${GREEN}✅ Internet connectivity confirmed${NC}"
        else
            log "WARN" "No internet connectivity yet. This may resolve after a few minutes."
            echo -e "${YELLOW}⚠️  No internet connectivity yet. DHCP may still be negotiating.${NC}"
        fi

    else
        log "INFO" "Not running OEM kernel, skipping network configuration"
    fi

    echo
}

# Function to configure security
configure_security() {
    log "INFO" "Configuring security settings..."

    # Install fail2ban if not already installed
    if ! command -v fail2ban-client >/dev/null 2>&1; then
        log "INFO" "Installing fail2ban..."
        apt install -y fail2ban
        systemctl enable --now fail2ban
    else
        log "INFO" "fail2ban already installed"
    fi

    # Configure SSH (only if not already configured)
    if ! grep -q "PasswordAuthentication no" /etc/ssh/sshd_config; then
        log "INFO" "Configuring SSH security..."
        sed -i \
            -e 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' \
            -e 's/^#\?PermitRootLogin .*/PermitRootLogin no/' \
            -e 's/^#\?PubkeyAuthentication .*/PubkeyAuthentication yes/' \
            /etc/ssh/sshd_config

        systemctl restart ssh
        log "INFO" "SSH security configured"
    else
        log "INFO" "SSH already configured securely"
    fi

    # Configure UFW (only if not already enabled)
    if ! ufw status | grep -q "Status: active"; then
        log "INFO" "Configuring UFW firewall..."
        ufw allow 22/tcp
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw --force enable
        log "INFO" "UFW firewall configured and enabled"
    else
        log "INFO" "UFW firewall already active"
    fi

    log "INFO" "Security configuration completed"
}

# Function to configure unattended upgrades
configure_unattended_upgrades() {
    log "INFO" "Checking unattended upgrades configuration..."

    # Check if already configured
    if [[ -f /etc/apt/apt.conf.d/50unattended-upgrades ]] && systemctl is-enabled unattended-upgrades >/dev/null 2>&1; then
        log "INFO" "Unattended upgrades already configured"
        return 0
    fi

    log "INFO" "Configuring unattended upgrades..."

    # Pre-configure unattended-upgrades to be non-interactive
    echo "unattended-upgrades unattended-upgrades/enable_auto_updates boolean true" | debconf-set-selections

    # Install unattended-upgrades if not already installed
    DEBIAN_FRONTEND=noninteractive apt install -y unattended-upgrades

    # Configure unattended upgrades to run automatically
    cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

Unattended-Upgrade::Package-Blacklist {
};

Unattended-Upgrade::DevRelease "false";
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
Unattended-Upgrade::SyslogEnable "true";
Unattended-Upgrade::SyslogFacility "daemon";
Unattended-Upgrade::Mail "root";
Unattended-Upgrade::MailReport "on-change";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
EOF

    # Enable unattended upgrades
    systemctl enable unattended-upgrades
    systemctl start unattended-upgrades

    log "INFO" "Unattended upgrades configured and enabled"
}

# Function to install security updates
install_security_updates() {
    log "INFO" "Installing security updates..."

    # Configure unattended upgrades first
    configure_unattended_upgrades

    # Install any pending security updates
    apt update
    apt upgrade -y

    # Install security packages
    apt install -y \
        unattended-upgrades \
        apt-listchanges \
        needrestart

    log "INFO" "Security updates installed"
}

# Function to install NVIDIA drivers
install_nvidia_drivers() {
    log "INFO" "Checking NVIDIA drivers..."

    if ! command -v nvidia-smi >/dev/null 2>&1; then
        log "INFO" "Installing NVIDIA drivers..."

        # Add NVIDIA CUDA repo for Ubuntu 24.04
        wget -qO- https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/3bf863cc.pub \
            | apt-key add - || true
        echo "deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/ /" \
            > /etc/apt/sources.list.d/nvidia-cuda.list

        apt update
        apt install -y nvidia-driver-575-open

        if [[ "$SKIP_REBOOT" != "true" ]]; then
            log "INFO" "Rebooting to load NVIDIA driver..."
            reboot
            exit 0
        else
            log "WARN" "Skipping reboot. Please reboot manually to load NVIDIA driver."
        fi
    else
        log "INFO" "NVIDIA drivers already installed"
    fi
}

# Function to verify NVIDIA driver
verify_nvidia() {
    log "INFO" "Verifying NVIDIA driver..."

    if ! nvidia-smi >/dev/null 2>&1; then
        log "ERROR" "NVIDIA driver not active"
        exit 1
    fi

    log "INFO" "NVIDIA driver verified successfully"
    nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader,nounits
}

# Function to install Docker
install_docker() {
    log "INFO" "Checking Docker installation..."

    # Check if Docker is already installed
    if command -v docker >/dev/null 2>&1 && systemctl is-active docker >/dev/null 2>&1; then
        log "INFO" "Docker already installed and running"
        return 0
    fi

    log "INFO" "Installing Docker CE..."

    apt install -y ca-certificates gnupg

    # Add Docker GPG key (non-interactive)
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/trusted.gpg.d/docker.gpg || true

    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/trusted.gpg.d/docker.gpg] \
        https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list

    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin

    # Start and enable Docker service
    systemctl enable docker
    systemctl start docker

    # Add user to docker group
    usermod -aG docker "$SYSTEM_USER"

    # Install Docker Compose v2
    log "INFO" "Installing Docker Compose v2..."

    # Create directory for Docker Compose
    mkdir -p "/home/$SYSTEM_USER/.docker/cli-plugins"

    # Download Docker Compose v2
    curl -SL "https://github.com/docker/compose/releases/download/v2.37.3/docker-compose-linux-x86_64" \
        -o "/home/$SYSTEM_USER/.docker/cli-plugins/docker-compose"
    chmod +x "/home/$SYSTEM_USER/.docker/cli-plugins/docker-compose"
    chown -R "$SYSTEM_USER:$SYSTEM_USER" "/home/$SYSTEM_USER/.docker"

    # Also install system-wide
    curl -SL "https://github.com/docker/compose/releases/download/v2.37.3/docker-compose-linux-x86_64" \
        -o "/usr/local/bin/docker-compose"
    chmod +x "/usr/local/bin/docker-compose"

    # Create symlink for docker compose (v2 syntax)
    ln -sf /usr/local/bin/docker-compose /usr/local/bin/docker-compose-v2

    log "INFO" "Docker installation completed"
}

# Function to install NVIDIA Container Toolkit
install_nvidia_container_toolkit() {
    log "INFO" "Checking NVIDIA Container Toolkit..."

    # Check if already installed
    if command -v nvidia-container-runtime >/dev/null 2>&1; then
        log "INFO" "NVIDIA Container Toolkit already installed"
        return 0
    fi

    log "INFO" "Installing NVIDIA Container Toolkit..."

    curl -sL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
        > /etc/apt/sources.list.d/nvidia-container-toolkit.list
    curl -sL https://nvidia.github.io/libnvidia-container/gpgkey \
        | gpg --dearmor -o /etc/apt/trusted.gpg.d/nvidia-container-toolkit.gpg || true

    apt update
    apt install -y nvidia-container-toolkit

    # Configure Docker to use NVIDIA runtime
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<'JSON'
{
  "default-runtime": "nvidia",
  "runtimes": {
    "nvidia": {
      "path": "nvidia-container-runtime",
      "runtimeArgs": []
    }
  }
}
JSON

    systemctl restart docker

    log "INFO" "NVIDIA Container Toolkit installed and configured"
}

# Function to test GPU in container
test_gpu_container() {
    log "INFO" "Testing GPU access in Docker container..."

    if docker run --rm --runtime=nvidia --gpus all \
        nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi; then
        log "INFO" "GPU container test successful"
    else
        log "WARN" "GPU container test failed - continuing anyway"
        log "INFO" "GPU access in containers may not work, but system will continue"
    fi
}

# Function to install native CUDA
install_native_cuda() {
    if [[ "${INSTALL_NATIVE_CUDA}" == "yes" ]]; then
        log "INFO" "Installing native CUDA toolkit..."

        # Install CUDA toolkit (without samples to avoid package issues)
        if apt install -y cuda-toolkit-12-9; then
            log "INFO" "CUDA toolkit installed successfully"

            # Set up CUDA environment variables
            if ! grep -q "CUDA_HOME" /etc/environment; then
                echo "CUDA_HOME=/usr/local/cuda-12.9" >> /etc/environment
                echo "PATH=\$PATH:/usr/local/cuda-12.9/bin" >> /etc/environment
                echo "LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:/usr/local/cuda-12.9/lib64" >> /etc/environment
                log "INFO" "CUDA environment variables configured"
            fi

            # Create symlinks for easier access
            ln -sf /usr/local/cuda-12.9/bin/nvcc /usr/local/bin/nvcc
            ln -sf /usr/local/cuda-12.9/bin/nvidia-smi /usr/local/bin/nvidia-smi

            # Try to install samples separately, but don't fail if not available
            if apt install -y cuda-samples-12-9 2>/dev/null; then
                log "INFO" "CUDA samples installed"

                # Build and test CUDA samples
                sudo -u "$SYSTEM_USER" bash -c '
                    cp -r /usr/local/cuda-12.9/samples "$HOME"/cuda-samples
                    cd "$HOME"/cuda-samples/1_Utilities/deviceQuery
                    make -j"$(nproc)" && ./deviceQuery
                ' 2>/dev/null || log "WARN" "CUDA samples build failed (this is normal)"
            else
                log "WARN" "CUDA samples package not available (this is normal)"
            fi

            log "INFO" "Native CUDA installation completed"
        else
            log "ERROR" "Failed to install CUDA toolkit"
            log "WARN" "Continuing without native CUDA (Docker CUDA still available)"
        fi
    else
        log "INFO" "Skipping native CUDA installation"
    fi
}

# Function to enable NVIDIA persistence daemon
enable_nvidia_persistence() {
    log "INFO" "Enabling NVIDIA persistence daemon..."
    systemctl enable --now nvidia-persistenced
    log "INFO" "NVIDIA persistence daemon enabled"
}

# Function to create system user and directories
setup_user_environment() {
    log "INFO" "Setting up user environment..."

    # Create system user if it doesn't exist
    if ! id "$SYSTEM_USER" >/dev/null 2>&1; then
        log "INFO" "Creating system user: $SYSTEM_USER"
        useradd -m -s /bin/bash "$SYSTEM_USER"

        # Set up SSH key if available
        if [[ -f "/root/.ssh/authorized_keys" ]]; then
            mkdir -p "/home/$SYSTEM_USER/.ssh"
            cp /root/.ssh/authorized_keys "/home/$SYSTEM_USER/.ssh/"
            chown -R "$SYSTEM_USER:$SYSTEM_USER" "/home/$SYSTEM_USER/.ssh"
            chmod 700 "/home/$SYSTEM_USER/.ssh"
            chmod 600 "/home/$SYSTEM_USER/.ssh/authorized_keys"
            log "INFO" "SSH keys copied to $SYSTEM_USER"
        fi

        # Add user to sudo group
        usermod -aG sudo "$SYSTEM_USER"
        log "INFO" "User $SYSTEM_USER created and added to sudo group"
    else
        log "INFO" "User $SYSTEM_USER already exists"
    fi

    # Create installation directory
    mkdir -p "$INSTALL_DIR"
    chown "$SYSTEM_USER:$SYSTEM_USER" "$INSTALL_DIR"

    # Create log directory
    mkdir -p /var/log/odins-ai
    chown "$SYSTEM_USER:$SYSTEM_USER" /var/log/odins-ai

    log "INFO" "User environment setup completed"
}

# Function to install AI/ML dependencies
install_ai_dependencies() {
    log "INFO" "Checking AI/ML dependencies..."

    # Check if Python is already installed
    if command -v python3 >/dev/null 2>&1 && command -v pip3 >/dev/null 2>&1; then
        log "INFO" "Python and pip already installed"
    else
        log "INFO" "Installing Python and pip..."
        apt install -y python3 python3-pip python3-venv
    fi

    # Install additional AI/ML packages (only if not already installed)
    local ai_packages=(
        libblas-dev liblapack-dev libatlas-base-dev
        libhdf5-dev libhdf5-serial-dev
        libjpeg-dev libpng-dev libtiff-dev
        libavcodec-dev libavformat-dev libswscale-dev
        libv4l-dev libxvidcore-dev libx264-dev
        libgtk-3-dev libcanberra-gtk3-module
        libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
    )

    local packages_to_install=()
    for package in "${ai_packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            packages_to_install+=("$package")
        fi
    done

    if [[ ${#packages_to_install[@]} -gt 0 ]]; then
        log "INFO" "Installing AI/ML packages: ${packages_to_install[*]}"
        apt install -y "${packages_to_install[@]}"
    else
        log "INFO" "All AI/ML packages already installed"
    fi

    log "INFO" "AI/ML dependencies installation completed"
}

# Function to create deployment summary
create_summary() {
    log "INFO" "Creating deployment summary..."

    cat > "$INSTALL_DIR/deployment-summary.txt" <<EOF
Odin AI Deployment Summary
==========================
Deployment Date: $(date)
System: $(uname -a)
Kernel: $(uname -r)
NVIDIA Driver: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits 2>/dev/null || echo "Not available")
Docker Version: $(docker --version)
CUDA Version: $(nvcc --version 2>/dev/null | grep release | awk '{print $6}' || echo "Not available")

Installation Directory: $INSTALL_DIR
System User: $SYSTEM_USER
Timezone: $TIMEZONE

Services Status:
- SSH: $(systemctl is-active ssh)
- Docker: $(systemctl is-active docker)
- UFW: $(systemctl is-active ufw)
- Fail2Ban: $(systemctl is-active fail2ban)
- NVIDIA Persistence: $(systemctl is-active nvidia-persistenced)

Next Steps:
1. Reboot the system if not done already
2. Test AI workloads
3. Configure additional services as needed
4. Set up monitoring and logging

For support, check the logs at: $LOG_FILE
EOF

    log "INFO" "Deployment summary created at $INSTALL_DIR/deployment-summary.txt"
}

# Function to configure performance settings
configure_performance() {
    log "INFO" "Configuring performance settings..."

    # Set CPU governor to performance
    if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]]; then
        log "INFO" "Setting CPU governor to performance mode..."
        echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1

        # Make it persistent across reboots
        if ! grep -q "cpufreq" /etc/default/grub; then
            sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="cpufreq.default_governor=performance /' /etc/default/grub
            update-grub
        fi
        log "INFO" "CPU governor set to performance mode"
    else
        log "WARN" "CPU governor not available"
    fi

    # Optimize memory settings
    if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
        echo "vm.swappiness=10" >> /etc/sysctl.conf
        echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.conf
        sysctl -p
        log "INFO" "Memory optimization settings applied"
    fi

    log "INFO" "Performance configuration completed"
}

# Function to create AI directories and install libraries
setup_ai_environment() {
    log "INFO" "Setting up AI environment..."

    # Create AI directories
    local ai_dirs=(
        "/opt/ai"
        "/opt/ai/models"
        "/opt/ai/huggingface"
        "/opt/ai/transformers"
        "/opt/ai/datasets"
    )

    for dir in "${ai_dirs[@]}"; do
        mkdir -p "$dir"
        chown "$SYSTEM_USER:$SYSTEM_USER" "$dir"
        log "INFO" "Created directory: $dir"
    done

    # Install AI/ML Python libraries
    log "INFO" "Installing AI/ML Python libraries..."

    # Add user's local bin to PATH
    if ! grep -q ".local/bin" "/home/$SYSTEM_USER/.bashrc"; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "/home/$SYSTEM_USER/.bashrc"
        log "INFO" "Added .local/bin to PATH"
    fi

    # Install PyTorch with CUDA support
    if ! python3 -c "import torch" 2>/dev/null; then
        log "INFO" "Installing PyTorch with CUDA support..."
        sudo -u "$SYSTEM_USER" pip3 install --break-system-packages --no-warn-script-location torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
        log "INFO" "PyTorch installed successfully"
    else
        log "INFO" "PyTorch already installed"
    fi

    # Install TensorFlow
    if ! python3 -c "import tensorflow" 2>/dev/null; then
        log "INFO" "Installing TensorFlow..."
        sudo -u "$SYSTEM_USER" pip3 install --break-system-packages --no-warn-script-location tensorflow
        log "INFO" "TensorFlow installed successfully"
    else
        log "INFO" "TensorFlow already installed"
    fi

    # Install other AI libraries
    local ai_libraries=(
        "transformers"
        "diffusers"
        "accelerate"
        "datasets"
        "huggingface-hub"
        "scikit-learn"
        "matplotlib"
        "seaborn"
        "pandas"
        "numpy"
        "jupyter"
        "ipywidgets"
    )

    for lib in "${ai_libraries[@]}"; do
        if ! python3 -c "import $lib" 2>/dev/null; then
            log "INFO" "Installing $lib..."
            sudo -u "$SYSTEM_USER" pip3 install --break-system-packages --no-warn-script-location "$lib"
        fi
    done

    log "INFO" "AI environment setup completed"
}

# Main execution function
main() {
    log "INFO" "Starting Odin AI deployment..."
    log "INFO" "Log file: $LOG_FILE"

    check_root
    check_system
    update_system
    configure_time
    install_oem_kernel
    configure_networking
    configure_security
    install_security_updates
    setup_user_environment
    install_nvidia_drivers
    verify_nvidia
    install_docker
    install_nvidia_container_toolkit
    test_gpu_container
    install_native_cuda
    enable_nvidia_persistence
    install_ai_dependencies
    configure_performance
    setup_ai_environment
    create_summary

    log "INFO" "✅ Odin AI workstation setup complete!"
    log "INFO" "Please review the deployment summary at: $INSTALL_DIR/deployment-summary.txt"

    if [[ "$SKIP_REBOOT" != "true" ]]; then
        echo -e "${GREEN}🎉 Deployment completed successfully!${NC}"
        echo -e "${YELLOW}⚠️  A reboot may be required to complete the setup.${NC}"
    else
        echo -e "${GREEN}🎉 Deployment completed successfully!${NC}"
        echo -e "${YELLOW}⚠️  Please reboot manually to complete the setup.${NC}"
    fi
}

# Run main function
main "$@"
