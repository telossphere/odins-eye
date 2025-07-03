#!/usr/bin/env bash
set -euo pipefail

# Set non-interactive mode for all package installations
export DEBIAN_FRONTEND=noninteractive

# ──────────────────────────────────────────────────────────────
# Odin AI Complete Deployment Script ©2025
# Combines host system setup + Docker services deployment
# ──────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="/var/log/odins-ai-complete-deployment.log"
CONFIG_FILE="$PROJECT_ROOT/config/deployment.conf"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
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
: "${INSTALL_DIR:=/opt/odins-ai}"
: "${SYSTEM_USER:=${SUDO_USER:-$(who am i | awk '{print $1}')}}"
: "${SKIP_REBOOT:=false}"
: "${SKIP_DOCKER_SERVICES:=false}"
: "${DOCKER_COMPOSE_VERSION:=v2.37.3}"

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}❌ Please run as root: sudo $0${NC}" >&2
        exit 1
    fi
}

# Function to print header
print_header() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              Odin AI Complete Deployment                    ║${NC}"
    echo -e "${CYAN}║           Host System + Docker Services                    ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
}

# Function to print section
print_section() {
    local title="$1"
    echo -e "${PURPLE}${title}${NC}"
    echo -e "${PURPLE}$(printf '%.0s─' {1..50})${NC}"
}

# Function to run host deployment
run_host_deployment() {
    print_section "Phase 1: Host System Deployment"

    log "INFO" "Starting host system deployment..."

    # Check if we need to run the host deployment
    if [[ -f "$INSTALL_DIR/deployment-summary.txt" ]]; then
        log "INFO" "Host deployment already completed, checking for missing components..."

        # Check if critical components are missing
        local missing_components=false

        # Check for CUDA toolkit
        if ! command -v nvcc >/dev/null 2>&1; then
            log "WARN" "CUDA toolkit (nvcc) not found"
            missing_components=true
        fi

        # Check for AI libraries
        if ! python3 -c "import torch" 2>/dev/null; then
            log "WARN" "PyTorch not found"
            missing_components=true
        fi

        if ! python3 -c "import tensorflow" 2>/dev/null; then
            log "WARN" "TensorFlow not found"
            missing_components=true
        fi

        # Check for AI directories
        if [[ ! -d "/opt/ai/models" ]] || [[ ! -d "/opt/ai/huggingface" ]]; then
            log "WARN" "AI directories missing"
            missing_components=true
        fi

        if [[ "$missing_components" == "true" ]]; then
            log "INFO" "Missing components detected, running host deployment..."
            echo -e "${YELLOW}⚠️  Missing components detected. Running host deployment...${NC}"
        else
            log "INFO" "Host deployment already completed, skipping..."
            echo -e "${YELLOW}⚠️  Host deployment already completed. Skipping to Docker services.${NC}"
            echo -e "${YELLOW}   To force reinstall, delete: $INSTALL_DIR/deployment-summary.txt${NC}"
            return 0
        fi
    fi

    # Run the host deployment script
    if [[ -f "$SCRIPT_DIR/deploy.sh" ]]; then
        log "INFO" "Running host deployment script..."
        echo -e "${BLUE}🔄 Running host system deployment...${NC}"

        # Set environment variable to skip reboots during complete deployment
        export SKIP_REBOOT=true

        if bash "$SCRIPT_DIR/deploy.sh"; then
            log "INFO" "Host deployment completed successfully"
            echo -e "${GREEN}✅ Host system deployment completed!${NC}"
        else
            log "ERROR" "Host deployment failed"
            echo -e "${RED}❌ Host deployment failed. Check logs: $LOG_FILE${NC}"
            return 1
        fi
    else
        log "ERROR" "Host deployment script not found: $SCRIPT_DIR/deploy.sh"
        echo -e "${RED}❌ Host deployment script not found${NC}"
        return 1
    fi

    echo
}

# Function to check and configure networking
check_networking() {
    print_section "Phase 1.5: Network Configuration Check"

    log "INFO" "Checking network configuration..."
    echo -e "${BLUE}🔄 Checking network configuration...${NC}"

    # Check if we have an IP address
    local ip_address=$(hostname -I | awk '{print $1}')

    if [[ -n "$ip_address" && "$ip_address" != "127.0.0.1" ]]; then
        log "INFO" "Network configured with IP: $ip_address"
        echo -e "${GREEN}✅ Network configured: $ip_address${NC}"

        # Test internet connectivity
        if curl -s --max-time 10 https://google.com >/dev/null; then
            log "INFO" "Internet connectivity confirmed"
            echo -e "${GREEN}✅ Internet connectivity confirmed${NC}"
            return 0
        else
            log "WARN" "No internet connectivity"
            echo -e "${YELLOW}⚠️  No internet connectivity${NC}"
        fi
    else
        log "WARN" "No IP address assigned"
        echo -e "${YELLOW}⚠️  No IP address assigned${NC}"
    fi

    # If we don't have proper networking, try to configure it
    if uname -r | grep -q '6\.11'; then
        log "INFO" "Attempting to configure network interfaces..."
        echo -e "${BLUE}🔄 Attempting to configure network interfaces...${NC}"

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
                log "ERROR" "No ethernet interface found"
                echo -e "${RED}❌ No ethernet interface found${NC}"
                return 1
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
            local new_ip_address=$(hostname -I | awk '{print $1}')
            if [[ -n "$new_ip_address" && "$new_ip_address" != "127.0.0.1" ]]; then
                log "INFO" "Network configured successfully. IP address: $new_ip_address"
                echo -e "${GREEN}✅ Network configured: $primary_interface -> $new_ip_address${NC}"

                # Test internet connectivity
                if curl -s --max-time 10 https://google.com >/dev/null; then
                    log "INFO" "Internet connectivity confirmed"
                    echo -e "${GREEN}✅ Internet connectivity confirmed${NC}"
                    return 0
                else
                    log "WARN" "No internet connectivity yet"
                    echo -e "${YELLOW}⚠️  No internet connectivity yet. DHCP may still be negotiating.${NC}"
                fi
            else
                log "WARN" "No IP address assigned yet"
                echo -e "${YELLOW}⚠️  No IP address assigned yet. DHCP may still be negotiating.${NC}"
            fi
        else
            log "ERROR" "Failed to apply Netplan configuration"
            echo -e "${RED}❌ Failed to apply network configuration${NC}"
            return 1
        fi
    else
        log "INFO" "Not running OEM kernel, network configuration may not be needed"
        echo -e "${YELLOW}⚠️  Not running OEM kernel. Network may need manual configuration.${NC}"
    fi

    echo
}

# Function to setup system user
setup_system_user() {
    print_section "Phase 1.6: System User Setup"

    log "INFO" "Setting up system user..."
    echo -e "${BLUE}🔄 Setting up system user...${NC}"

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
        echo -e "${GREEN}✅ User $SYSTEM_USER created${NC}"
    else
        log "INFO" "User $SYSTEM_USER already exists"
        echo -e "${GREEN}✅ User $SYSTEM_USER already exists${NC}"
    fi

    # Ensure user is in docker group
    if ! groups "$SYSTEM_USER" | grep -q docker; then
        log "INFO" "Adding $SYSTEM_USER to docker group"
        usermod -aG docker "$SYSTEM_USER"
        echo -e "${GREEN}✅ User $SYSTEM_USER added to docker group${NC}"
    else
        log "INFO" "User $SYSTEM_USER already in docker group"
        echo -e "${GREEN}✅ User $SYSTEM_USER already in docker group${NC}"
    fi

    echo
}

# Function to wait for Docker to be ready
wait_for_docker() {
    print_section "Phase 2: Docker Service Check"

    log "INFO" "Waiting for Docker service to be ready..."
    echo -e "${BLUE}🔄 Waiting for Docker service...${NC}"

    local max_attempts=30
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if systemctl is-active docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
            log "INFO" "Docker service is ready"
            echo -e "${GREEN}✅ Docker service is ready!${NC}"
            return 0
        fi

        echo -e "${YELLOW}⏳ Waiting for Docker... (attempt $attempt/$max_attempts)${NC}"
        sleep 2
        ((attempt++))
    done

    log "ERROR" "Docker service failed to start within timeout"
    echo -e "${RED}❌ Docker service failed to start${NC}"
    return 1
}

# Function to verify Docker GPU support
verify_docker_gpu() {
    print_section "Phase 3: Docker GPU Verification"

    log "INFO" "Verifying Docker GPU support..."
    echo -e "${BLUE}🔄 Verifying Docker GPU support...${NC}"

    if docker run --rm --runtime=nvidia --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi >/dev/null 2>&1; then
        log "INFO" "Docker GPU support verified"
        echo -e "${GREEN}✅ Docker GPU support verified!${NC}"
        return 0
    else
        log "ERROR" "Docker GPU support verification failed"
        echo -e "${RED}❌ Docker GPU support verification failed${NC}"
        echo -e "${YELLOW}⚠️  Continuing without GPU support in containers${NC}"
        return 1
    fi
}

# Function to verify Docker Compose installation
verify_docker_compose() {
    log "INFO" "Verifying Docker Compose installation..."

    # Check if docker compose works
    if docker compose version >/dev/null 2>&1; then
        log "INFO" "Docker Compose v2 verified"
        echo -e "${GREEN}✅ Docker Compose v2 verified!${NC}"
        return 0
    elif command -v docker-compose >/dev/null 2>&1; then
        log "INFO" "Docker Compose v1 verified"
        echo -e "${GREEN}✅ Docker Compose v1 verified!${NC}"
        return 0
    else
        log "ERROR" "Docker Compose not found"
        echo -e "${RED}❌ Docker Compose not found${NC}"
        return 1
    fi
}

# Function to setup Docker Compose
setup_docker_compose() {
    print_section "Phase 4: Docker Compose Setup"

    log "INFO" "Setting up Docker Compose..."
    echo -e "${BLUE}🔄 Setting up Docker Compose...${NC}"

    # Check if Docker Compose is already installed
    if docker compose version >/dev/null 2>&1; then
        log "INFO" "Docker Compose already installed"
        echo -e "${GREEN}✅ Docker Compose already installed${NC}"
        return 0
    fi

    # Install Docker Compose for the system user
    log "INFO" "Installing Docker Compose..."

    # Create directory for Docker Compose
    mkdir -p "/home/$SYSTEM_USER/.docker/cli-plugins"

    # Download Docker Compose
    curl -SL "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-linux-x86_64" \
        -o "/home/$SYSTEM_USER/.docker/cli-plugins/docker-compose"

    # Set permissions
    chmod +x "/home/$SYSTEM_USER/.docker/cli-plugins/docker-compose"
    chown -R "$SYSTEM_USER:$SYSTEM_USER" "/home/$SYSTEM_USER/.docker"

    # Also install system-wide
    curl -SL "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-linux-x86_64" \
        -o "/usr/local/bin/docker-compose"
    chmod +x "/usr/local/bin/docker-compose"

    # Create symlink for docker compose (v2 syntax)
    ln -sf /usr/local/bin/docker-compose /usr/local/bin/docker-compose-v2

    # Verify installation
    if docker compose version >/dev/null 2>&1; then
        log "INFO" "Docker Compose installed successfully"
        echo -e "${GREEN}✅ Docker Compose installed!${NC}"
    else
        log "ERROR" "Docker Compose installation failed"
        echo -e "${RED}❌ Docker Compose installation failed${NC}"
        return 1
    fi
}

# Function to create Docker configuration files
create_docker_configs() {
    print_section "Phase 5: Docker Configuration"

    log "INFO" "Creating Docker configuration files..."
    echo -e "${BLUE}🔄 Creating Docker configuration files...${NC}"

    local docker_config_dir="$PROJECT_ROOT/docker/config"
    mkdir -p "$docker_config_dir"

    # Create Prometheus configuration
    cat > "$docker_config_dir/prometheus.yml" <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  # - "first_rules.yml"
  # - "second_rules.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'odins-ai'
    static_configs:
      - targets: ['odins-ai:8080']
EOF

    # Create Nginx configuration
    cat > "$docker_config_dir/nginx.conf" <<'EOF'
events {
    worker_connections 1024;
}

http {
    upstream odins_ai {
        server odins-ai:8080;
    }

    upstream grafana {
        server grafana:3000;
    }

    upstream jupyter {
        server jupyter:8888;
    }

    server {
        listen 80;
        server_name localhost;

        location / {
            proxy_pass http://odins_ai;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        location /grafana/ {
            proxy_pass http://grafana/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        location /jupyter/ {
            proxy_pass http://jupyter/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
EOF

    # Create Grafana provisioning directory
    mkdir -p "$docker_config_dir/grafana/provisioning/datasources"
    mkdir -p "$docker_config_dir/grafana/provisioning/dashboards"

    # Create Prometheus datasource
    cat > "$docker_config_dir/grafana/provisioning/datasources/prometheus.yml" <<'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
EOF

    # Create dashboard provisioning
    cat > "$docker_config_dir/grafana/provisioning/dashboards/dashboard.yml" <<'EOF'
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/provisioning/dashboards
EOF

    log "INFO" "Docker configuration files created"
    echo -e "${GREEN}✅ Docker configuration files created!${NC}"
}

# Function to check port availability
check_port_availability() {
    print_section "Phase 5.5: Port Availability Check"

    log "INFO" "Checking port availability..."
    echo -e "${BLUE}🔄 Checking port availability...${NC}"

    local ports=("80" "443" "8080" "3001" "3002" "3003" "3004" "7860" "8888" "9090" "5432" "6379" "9100")
    local conflicts=()
    local docker_services=()
    local system_services=()

    for port in "${ports[@]}"; do
        local port_in_use=false
        local is_docker_service=false
        local is_system_service=false

        # Check if port is in use
        if netstat -tlnp 2>/dev/null | grep -q ":$port "; then
            port_in_use=true
            conflicts+=("$port")

            # Get process info for the port
            local port_info=$(netstat -tlnp 2>/dev/null | grep ":$port " | head -1)
            local process_info=""

            if [[ -n "$port_info" ]]; then
                # Extract process ID and name
                local process_pid=$(echo "$port_info" | awk '{print $7}' | cut -d'/' -f1)
                local process_name=$(echo "$port_info" | awk '{print $7}' | cut -d'/' -f2)

                if [[ -n "$process_pid" && "$process_pid" != "-" ]]; then
                    # Check if it's a Docker-related process
                    if [[ "$process_name" == "docker" ]] || \
                       [[ "$process_name" == "containerd" ]] || \
                       [[ "$process_name" == "dockerd" ]] || \
                       [[ "$process_name" == "docker-proxy" ]]; then
                        is_docker_service=true
                    else
                        # Check process name more thoroughly
                        local actual_process=$(ps -p "$process_pid" -o comm= 2>/dev/null)
                        if [[ -n "$actual_process" ]]; then
                            if [[ "$actual_process" == "docker" ]] || \
                               [[ "$actual_process" == "containerd" ]] || \
                               [[ "$actual_process" == "dockerd" ]] || \
                               [[ "$actual_process" == "docker-proxy" ]] || \
                               [[ "$actual_process" =~ docker ]]; then
                                is_docker_service=true
                            elif [[ "$actual_process" == "nginx" ]] || \
                                  [[ "$actual_process" == "apache2" ]] || \
                                  [[ "$actual_process" == "httpd" ]] || \
                                  [[ "$actual_process" == "sshd" ]] || \
                                  [[ "$actual_process" == "postgres" ]] || \
                                  [[ "$actual_process" == "redis" ]]; then
                                is_system_service=true
                            fi
                        fi
                    fi
                fi
            fi

            # Also check Docker containers using this port
            if [[ "$is_docker_service" == "false" && "$is_system_service" == "false" ]]; then
                if docker ps --format "{{.Names}}" 2>/dev/null | while read -r container; do
                    if docker port "$container" 2>/dev/null | grep -q ":$port"; then
                        is_docker_service=true
                        return 0
                    fi
                done; then
                    # Check completed
                    :
                fi
            fi

            # Categorize the conflict
            if [[ "$is_docker_service" == "true" ]]; then
                docker_services+=("$port")
                log "INFO" "Port $port is in use by Docker service"
                echo -e "${GREEN}✅ Port $port is in use by Docker service${NC}"
            elif [[ "$is_system_service" == "true" ]]; then
                system_services+=("$port")
                log "INFO" "Port $port is in use by system service"
                echo -e "${BLUE}ℹ️  Port $port is in use by system service${NC}"
            else
                log "WARN" "Port $port is already in use by unknown process"
                echo -e "${YELLOW}⚠️  Port $port is already in use${NC}"
            fi
        else
            log "INFO" "Port $port is available"
            echo -e "${GREEN}✅ Port $port is available${NC}"
        fi
    done

    # Summary
    if [[ ${#conflicts[@]} -gt 0 ]]; then
        local docker_count=${#docker_services[@]}
        local system_count=${#system_services[@]}
        local unknown_count=$(( ${#conflicts[@]} - docker_count - system_count ))

        if [[ $docker_count -gt 0 ]]; then
            log "INFO" "Docker services using ports: ${docker_services[*]}"
            echo -e "${BLUE}ℹ️  Docker services using ports: ${docker_services[*]}${NC}"
        fi

        if [[ $system_count -gt 0 ]]; then
            log "INFO" "System services using ports: ${system_services[*]}"
            echo -e "${BLUE}ℹ️  System services using ports: ${system_services[*]}${NC}"
        fi

        if [[ $unknown_count -gt 0 ]]; then
            log "WARN" "Unknown processes using ports: ${conflicts[*]}"
            echo -e "${YELLOW}⚠️  Unknown processes using ports: ${conflicts[*]}${NC}"
            echo -e "${YELLOW}⚠️  Some services may not start properly${NC}"
        else
            log "INFO" "All port conflicts are from known services"
            echo -e "${GREEN}✅ All port conflicts are from known services${NC}"
            echo -e "${BLUE}💡 Services will be managed appropriately during deployment${NC}"
        fi
    else
        log "INFO" "All ports are available"
        echo -e "${GREEN}✅ All ports are available${NC}"
    fi

    echo
}

# Function to clean up conflicting Docker services
cleanup_conflicting_services() {
    print_section "Phase 5.6: Cleanup Conflicting Services"

    log "INFO" "Cleaning up conflicting Docker services..."
    echo -e "${BLUE}🔄 Cleaning up conflicting Docker services...${NC}"

    local docker_dir="$PROJECT_ROOT/docker"

    # Check if we're in a Docker Compose project
    if [[ -f "$docker_dir/docker-compose.yml" ]]; then
        cd "$docker_dir"

        # Stop any existing services from this project
        log "INFO" "Stopping existing Docker Compose services..."
        if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
            docker compose down 2>/dev/null || true
            log "INFO" "Stopped existing services with docker compose"
        elif command -v docker-compose >/dev/null 2>&1; then
            docker-compose down 2>/dev/null || true
            log "INFO" "Stopped existing services with docker-compose"
        fi

        cd "$PROJECT_ROOT"
    fi

    # Stop any containers that might be using our ports
    local ports=("80" "443" "8080" "3001" "3002" "3003" "3004" "7860" "8888" "9090" "5432" "6379" "9100")
    local stopped_containers=()

    for port in "${ports[@]}"; do
        # Find containers using this port
        local containers_using_port=$(docker ps --format "{{.Names}}" 2>/dev/null | while read -r container; do
            if docker port "$container" 2>/dev/null | grep -q ":$port"; then
                echo "$container"
            fi
        done)

        if [[ -n "$containers_using_port" ]]; then
            echo "$containers_using_port" | while read -r container; do
                if [[ -n "$container" ]]; then
                    log "INFO" "Stopping container $container using port $port"
                    docker stop "$container" 2>/dev/null || true
                    stopped_containers+=("$container")
                fi
            done
        fi
    done

    if [[ ${#stopped_containers[@]} -gt 0 ]]; then
        log "INFO" "Stopped ${#stopped_containers[@]} conflicting containers"
        echo -e "${GREEN}✅ Stopped ${#stopped_containers[@]} conflicting containers${NC}"
    else
        log "INFO" "No conflicting containers found"
        echo -e "${GREEN}✅ No conflicting containers found${NC}"
    fi

    # Wait a moment for ports to be released
    sleep 2

    echo
}

# Function to deploy Docker services
deploy_docker_services() {
    print_section "Phase 6: Docker Services Deployment"

    if [[ "$SKIP_DOCKER_SERVICES" == "true" ]]; then
        log "INFO" "Skipping Docker services deployment"
        echo -e "${YELLOW}⚠️  Skipping Docker services deployment${NC}"
        return 0
    fi

    log "INFO" "Deploying Docker services..."
    echo -e "${BLUE}🔄 Deploying Docker services...${NC}"

    local docker_dir="$PROJECT_ROOT/docker"

    # Check if Docker Compose file exists
    if [[ ! -f "$docker_dir/docker-compose.yml" ]]; then
        log "ERROR" "Docker Compose file not found: $docker_dir/docker-compose.yml"
        echo -e "${RED}❌ Docker Compose file not found${NC}"
        return 1
    fi

    # Change to Docker directory
    cd "$docker_dir"

    # Set environment variables for Docker Compose
    export POSTGRES_PASSWORD="odins_ai_secure_password_$(date +%s)"
    export GRAFANA_PASSWORD="admin"

    # Pull images first
    log "INFO" "Pulling Docker images..."
    echo -e "${BLUE}🔄 Pulling Docker images...${NC}"

    # Try docker compose first, fallback to docker-compose
    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        if docker compose pull; then
            log "INFO" "Docker images pulled successfully with docker compose"
        else
            log "ERROR" "Failed to pull Docker images with docker compose"
            echo -e "${RED}❌ Failed to pull Docker images${NC}"
            return 1
        fi
    elif command -v docker-compose >/dev/null 2>&1; then
        if docker-compose pull; then
            log "INFO" "Docker images pulled successfully with docker-compose"
        else
            log "ERROR" "Failed to pull Docker images with docker-compose"
            echo -e "${RED}❌ Failed to pull Docker images${NC}"
            return 1
        fi
    else
        log "ERROR" "Neither docker compose nor docker-compose found"
        echo -e "${RED}❌ Docker Compose not found. Please install Docker Compose first.${NC}"
        return 1
    fi

    # Start services
    log "INFO" "Starting Docker services..."
    echo -e "${BLUE}🔄 Starting Docker services...${NC}"

    # Try docker compose first, fallback to docker-compose
    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        # Stop existing services first (idempotent)
        log "INFO" "Stopping existing services..."
        docker compose down 2>/dev/null || true

        if docker compose up -d; then
            log "INFO" "Docker services started successfully"
            echo -e "${GREEN}✅ Docker services started!${NC}"

            # Wait for services to be ready
            log "INFO" "Waiting for services to be ready..."
            echo -e "${BLUE}🔄 Waiting for services to be ready...${NC}"
            sleep 10

            # Show service status
            docker compose ps

        else
            log "ERROR" "Failed to start Docker services with docker compose"
            echo -e "${RED}❌ Failed to start Docker services${NC}"
            return 1
        fi

    elif command -v docker-compose >/dev/null 2>&1; then
        # Stop existing services first (idempotent)
        log "INFO" "Stopping existing services..."
        docker-compose down 2>/dev/null || true

        if docker-compose up -d; then
            log "INFO" "Docker services started successfully (using docker-compose)"
            echo -e "${GREEN}✅ Docker services started!${NC}"

            # Wait for services to be ready
            log "INFO" "Waiting for services to be ready..."
            echo -e "${BLUE}🔄 Waiting for services to be ready...${NC}"
            sleep 10

            # Show service status
            docker-compose ps

        else
            log "ERROR" "Failed to start Docker services with docker-compose"
            echo -e "${RED}❌ Failed to start Docker services${NC}"
            return 1
        fi

    else
        log "ERROR" "Neither docker compose nor docker-compose found"
        echo -e "${RED}❌ Docker Compose not found. Please install Docker Compose first.${NC}"
        return 1
    fi

    # Return to original directory
    cd "$PROJECT_ROOT"
}

# Function to create service access information
create_access_info() {
    print_section "Phase 7: Service Access Information"

    log "INFO" "Creating service access information..."

    local access_file="$INSTALL_DIR/service-access.txt"

    # Get server IP addresses
    local local_ip=$(hostname -I | awk '{print $1}')
    local public_ip=$(curl -s --max-time 5 https://ipinfo.io/ip 2>/dev/null || echo "Not available")

    cat > "$access_file" <<EOF
Odin AI Complete Deployment - Service Access
============================================

Deployment completed: $(date)

🌐 Server Information:
- Local IP: $local_ip
- Public IP: $public_ip
- Hostname: $(hostname)

🌐 Web Services (Access from any device):
- Main Application: http://$local_ip:8080
- Stable Diffusion WebUI: http://$local_ip:7860
- Grafana Dashboard: http://$local_ip:3001 (admin/admin)
- Jupyter Lab: http://$local_ip:8888
- Prometheus: http://$local_ip:9090

🗄️ Database Services:
- PostgreSQL: $local_ip:5432 (odin/odins_ai_secure_password)
- Redis: $local_ip:6379

📊 Monitoring:
- Node Exporter: http://$local_ip:9100
- Nginx: http://$local_ip:80

🔧 Remote Management (from your MacBook/other devices):
- SSH Access: ssh odin@$local_ip
- Check status: ssh odin@$local_ip './scripts/status.sh'
- View logs: ssh odin@$local_ip 'tail -f /var/log/odins-ai-complete-deployment.log'
- Docker management: ssh odin@$local_ip 'cd docker && docker compose ps'

📁 Important Directories:
- Installation: $INSTALL_DIR
- AI Models: /opt/ai/models
- Logs: /var/log/odins-ai
- Docker Compose: $PROJECT_ROOT/docker

🔐 Security Notes:
- SSH keys required (password auth disabled)
- Firewall enabled (UFW)
- Fail2Ban active
- Root login disabled

🌍 Remote Access Setup:
1. From your MacBook, open a web browser
2. Navigate to: http://$local_ip:8080 (Main App)
3. Or: http://$local_ip:3000 (Grafana Dashboard)
4. For SSH: ssh odin@$local_ip

📞 Support:
- Logs: $LOG_FILE
- Verification: ./scripts/verify.sh
- Troubleshooting: ./scripts/troubleshoot.sh

🎉 Your Odin AI system is ready for production use!
EOF

    chown "$SYSTEM_USER:$SYSTEM_USER" "$access_file"

    log "INFO" "Service access information created"
    echo -e "${GREEN}✅ Service access information created!${NC}"

    # Display access information
    echo
    echo -e "${CYAN}📋 Service Access Information:${NC}"
    cat "$access_file"

    # Display remote access instructions
    echo
    echo -e "${YELLOW}🌍 Remote Access Instructions:${NC}"
    echo -e "From your MacBook or any other device:"
    echo -e "  🌐 Main App: ${GREEN}http://$local_ip:8080${NC}"
    echo -e "  🎨 Stable Diffusion: ${GREEN}http://$local_ip:7860${NC}"
    echo -e "  📊 Grafana: ${GREEN}http://$local_ip:3001${NC} (admin/admin)"
    echo -e "  📓 Jupyter: ${GREEN}http://$local_ip:8888${NC}"
    echo -e "  📈 Prometheus: ${GREEN}http://$local_ip:9090${NC}"
    echo -e "  🔧 SSH: ${GREEN}ssh odin@$local_ip${NC}"
    echo
    echo -e "${BLUE}💡 Tip: Bookmark these URLs on your MacBook for easy access!${NC}"
}

# Function to run verification
run_verification() {
    print_section "Phase 8: Final Verification"

    log "INFO" "Running final verification..."
    echo -e "${BLUE}🔄 Running final verification...${NC}"

    # Run the verification script
    if [[ -f "$SCRIPT_DIR/verify.sh" ]]; then
        if bash "$SCRIPT_DIR/verify.sh"; then
            log "INFO" "Verification completed successfully"
            echo -e "${GREEN}✅ Verification completed!${NC}"
        else
            log "WARN" "Verification found some issues"
            echo -e "${YELLOW}⚠️  Verification found some issues - check the output above${NC}"
        fi
    else
        log "WARN" "Verification script not found"
        echo -e "${YELLOW}⚠️  Verification script not found${NC}"
    fi

    echo
}

# Function to run Jupyter GPU verification
run_jupyter_verification() {
    print_section "Phase 8.5: Jupyter GPU Verification"

    log "INFO" "Running Jupyter GPU verification..."
    echo -e "${BLUE}🧪 Running Jupyter GPU verification tests...${NC}"

    # Wait longer for Jupyter to fully start and install PyTorch
    echo -e "${BLUE}⏳ Waiting for Jupyter to fully initialize and install PyTorch...${NC}"
    sleep 60  # Increased from 30 to 60 seconds

    # Run the Jupyter verification script
    if [[ -f "$SCRIPT_DIR/verify-jupyter.sh" ]]; then
        if bash "$SCRIPT_DIR/verify-jupyter.sh"; then
            log "INFO" "Jupyter GPU verification completed successfully"
            echo -e "${GREEN}✅ Jupyter GPU verification completed!${NC}"
        else
            log "WARN" "Jupyter GPU verification found some issues"
            echo -e "${YELLOW}⚠️  Jupyter GPU verification found some issues - check the output above${NC}"
            echo -e "${YELLOW}💡 You can manually run the verification later with: ./scripts/verify-jupyter.sh${NC}"
        fi
    else
        log "WARN" "Jupyter verification script not found"
        echo -e "${YELLOW}⚠️  Jupyter verification script not found${NC}"
    fi

    echo
}

# Function to print completion message
print_completion() {
    # Get server IP for display
    local local_ip=$(hostname -I | awk '{print $1}')

    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    🎉 DEPLOYMENT COMPLETE! 🎉                ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${GREEN}✅ Odin AI Complete Deployment Finished Successfully!${NC}"
    echo
    echo -e "${BLUE}📋 What's Available:${NC}"
    echo -e "  🌐 Main App: ${GREEN}http://$local_ip:8080${NC}"
    echo -e "  🎨 Stable Diffusion: ${GREEN}http://$local_ip:7860${NC}"
    echo -e "  📊 Grafana: ${GREEN}http://$local_ip:3001${NC} (admin/admin)"
    echo -e "  📓 Jupyter: ${GREEN}http://$local_ip:8888${NC}"
    echo -e "  📈 Prometheus: ${GREEN}http://$local_ip:9090${NC}"
    echo
    echo -e "${BLUE}🔧 Remote Management:${NC}"
    echo -e "  SSH Access: ${GREEN}ssh odin@$local_ip${NC}"
    echo -e "  Status: ${GREEN}ssh odin@$local_ip './scripts/status.sh'${NC}"
    echo -e "  Logs: ${GREEN}ssh odin@$local_ip 'tail -f $LOG_FILE'${NC}"
    echo -e "  Docker: ${GREEN}ssh odin@$local_ip 'cd docker && docker compose ps'${NC}"
    echo
    echo -e "${BLUE}📁 Files:${NC}"
    echo -e "  Access Info: ${GREEN}$INSTALL_DIR/service-access.txt${NC}"
    echo -e "  Deployment Log: ${GREEN}$LOG_FILE${NC}"
    echo
    echo -e "${YELLOW}⚠️  Next Steps:${NC}"
    echo -e "  1. From your MacBook, open a web browser"
    echo -e "  2. Navigate to: ${GREEN}http://$local_ip:8080${NC}"
    echo -e "  3. Configure your AI models and applications"
    echo -e "  4. Set up monitoring dashboards in Grafana"
    echo -e "  5. Configure backups and security policies"
    echo
    echo -e "${CYAN}🚀 Your Odin AI system is ready for production!${NC}"
    echo -e "${CYAN}💡 Bookmark these URLs on your MacBook for easy access!${NC}"
}

# Main execution function
main() {
    check_root
    print_header

    log "INFO" "Starting complete Odin AI deployment..."
    log "INFO" "Log file: $LOG_FILE"

    # Create log directory
    mkdir -p "$(dirname "$LOG_FILE")"

    # Run deployment phases
    run_host_deployment
    check_networking
    setup_system_user
    wait_for_docker
    verify_docker_gpu
    verify_docker_compose
    setup_docker_compose
    create_docker_configs
    check_port_availability
    cleanup_conflicting_services
    deploy_docker_services
    create_access_info
    run_verification
    run_jupyter_verification

    log "INFO" "Complete deployment finished successfully"
    print_completion
}

# Run main function
main "$@"
