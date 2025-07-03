#!/bin/bash

# Odin's Eye Platform - One-Command Deployment Script
# Deploys the complete Odin's Eye platform with all services

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}🚀 Odin's Eye Platform Deployment${NC}"
echo -e "${CYAN}Complete AI/ML Platform with GPU Support${NC}"
echo

check_prerequisites() {
    echo -e "${BLUE}🔍 Checking prerequisites...${NC}"
    if [[ $EUID -eq 0 ]]; then
        echo -e "${RED}❌ Please do not run as root. Use a regular user with sudo access.${NC}"
        exit 1
    fi
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${RED}❌ Docker is not installed. Please install Docker first.${NC}"
        exit 1
    fi
    if ! docker compose version >/dev/null 2>&1; then
        echo -e "${RED}❌ Docker Compose is not installed. Please install Docker Compose first.${NC}"
        exit 1
    fi
    if ! docker info >/dev/null 2>&1; then
        echo -e "${RED}❌ Docker is not running. Please start Docker first.${NC}"
        exit 1
    fi
    if ! docker run --rm --gpus all nvidia/cuda:12.8.0-base-ubuntu22.04 nvidia-smi >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  NVIDIA Docker support not available. GPU features will be limited.${NC}"
    else
        echo -e "${GREEN}✅ NVIDIA Docker support available${NC}"
    fi
    echo -e "${GREEN}✅ Prerequisites check passed${NC}"
}

create_directories() {
    echo -e "${BLUE}📁 Creating necessary directories...${NC}"
    mkdir -p ./data/redis
    mkdir -p ./data/postgres
    mkdir -p ./data/prometheus
    mkdir -p ./data/grafana
    mkdir -p ./logs
    mkdir -p ./models
    mkdir -p ./config
    chmod 755 ./data ./logs ./models ./config
    echo -e "${GREEN}✅ Directories created${NC}"
}

create_docker_configs() {
    echo -e "${BLUE}⚙️  Creating Docker configuration files...${NC}"

    # Create Prometheus configuration
    cat > ./docker/config/prometheus.yml << 'PROMETHEUS_EOF'
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

  - job_name: 'odins-eye'
    static_configs:
      - targets: ['odins-eye:8080']
PROMETHEUS_EOF

    # Create Nginx configuration
    cat > ./docker/config/nginx.conf << 'NGINX_EOF'
events {
    worker_connections 1024;
}

http {
    upstream odins_eye {
        server odins-eye:8080;
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
            proxy_pass http://odins_eye;
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
NGINX_EOF

    # Create Grafana provisioning
    mkdir -p ./docker/config/grafana/provisioning/datasources
    mkdir -p ./docker/config/grafana/provisioning/dashboards

    # Create Prometheus datasource
    cat > ./docker/config/grafana/provisioning/datasources/prometheus.yml << 'GRAFANA_DS_EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
GRAFANA_DS_EOF

    # Create dashboard provisioning
    cat > ./docker/config/grafana/provisioning/dashboards/dashboard.yml << 'GRAFANA_DASH_EOF'
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
GRAFANA_DASH_EOF

    echo -e "${GREEN}✅ Docker configuration files created${NC}"
}

stop_existing() {
    echo -e "${BLUE}🛑 Stopping existing containers...${NC}"
    cd docker
    docker compose down --remove-orphans 2>/dev/null || true
    cd ..
    echo -e "${GREEN}✅ Existing containers stopped${NC}"
}

deploy_services() {
    echo -e "${BLUE}🔨 Building and starting services...${NC}"
    echo -e "${YELLOW}This may take 5-10 minutes for the initial build...${NC}"

    cd docker
    docker compose build --no-cache
    docker compose up -d
    cd ..

    echo -e "${GREEN}✅ Services started${NC}"
}

wait_for_services() {
    echo -e "${BLUE}⏳ Waiting for services to be ready...${NC}"

    # Wait for main app
    local max_attempts=60
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if curl -s "http://localhost:8080/api/health" > /dev/null 2>&1; then
            echo -e "${GREEN}✅ Main application is ready!${NC}"
            break
        fi

        echo -e "${YELLOW}Attempt $attempt/$max_attempts - Main app not ready yet...${NC}"
        sleep 10
        ((attempt++))
    done

    if [ $attempt -gt $max_attempts ]; then
        echo -e "${RED}❌ Main application failed to start within expected time${NC}"
        return 1
    fi

    # Wait for Jupyter
    attempt=1
    while [ $attempt -le $max_attempts ]; do
        if curl -s "http://localhost:8888" > /dev/null 2>&1; then
            echo -e "${GREEN}✅ Jupyter Lab is ready!${NC}"
            break
        fi

        echo -e "${YELLOW}Attempt $attempt/$max_attempts - Jupyter not ready yet...${NC}"
        sleep 10
        ((attempt++))
    done

    if [ $attempt -gt $max_attempts ]; then
        echo -e "${YELLOW}⚠️  Jupyter Lab may still be starting up...${NC}"
    fi

    # Wait for Grafana
    attempt=1
    while [ $attempt -le $max_attempts ]; do
        if curl -s "http://localhost:3001" > /dev/null 2>&1; then
            echo -e "${GREEN}✅ Grafana is ready!${NC}"
            break
        fi

        echo -e "${YELLOW}Attempt $attempt/$max_attempts - Grafana not ready yet...${NC}"
        sleep 10
        ((attempt++))
    done

    if [ $attempt -gt $max_attempts ]; then
        echo -e "${YELLOW}⚠️  Grafana may still be starting up...${NC}"
    fi
}

show_status() {
    echo -e "${BLUE}📊 Service Status:${NC}"
    cd docker
    docker compose ps
    cd ..

    echo -e "\n${BLUE}📋 Container Logs:${NC}"
    cd docker
    docker compose logs --tail=10
    cd ..
}

show_access_info() {
    echo -e "\n${GREEN}🎉 Deployment Complete!${NC}"
    echo -e "${BLUE}Access Information:${NC}"
    echo -e "  • Main Dashboard: ${GREEN}http://localhost:8080${NC}"
    echo -e "  • Jupyter Lab: ${GREEN}http://localhost:8888${NC}"
    echo -e "  • Grafana: ${GREEN}http://localhost:3001${NC} (admin/admin)"
    echo -e "  • Prometheus: ${GREEN}http://localhost:9090${NC}"
    echo -e "  • Node Exporter: ${GREEN}http://localhost:9100${NC}"
    echo -e "  • PostgreSQL: ${GREEN}localhost:5432${NC}"
    echo -e "  • Redis: ${GREEN}localhost:6379${NC}"
    echo
    echo -e "${YELLOW}Next Steps:${NC}"
    echo -e "  1. Access the main dashboard at http://localhost:8080"
    echo -e "  2. Open Jupyter Lab at http://localhost:8888 for development"
    echo -e "  3. Configure Grafana dashboards at http://localhost:3001"
    echo -e "  4. Check GPU monitoring at http://localhost:8080/gpu"
    echo
    echo -e "${BLUE}Useful Commands:${NC}"
    echo -e "  • View logs: ${GREEN}cd docker && docker compose logs -f${NC}"
    echo -e "  • Stop: ${GREEN}cd docker && docker compose down${NC}"
    echo -e "  • Restart: ${GREEN}cd docker && docker compose restart${NC}"
    echo -e "  • Status: ${GREEN}./scripts/status.sh${NC}"
    echo -e "  • Verify: ${GREEN}./scripts/verify.sh${NC}"
    echo -e "  • Troubleshoot: ${GREEN}./scripts/troubleshoot.sh${NC}"
}

main() {
    echo -e "${BLUE}🔍 Pre-deployment checks...${NC}"
    check_prerequisites
    create_directories
    create_docker_configs

    echo -e "\n${BLUE}🚀 Starting deployment...${NC}"
    stop_existing
    deploy_services

    echo -e "\n${BLUE}⏳ Waiting for services to be ready...${NC}"
    if wait_for_services; then
        show_status
        show_access_info
    else
        echo -e "${RED}❌ Deployment failed${NC}"
        show_status
        exit 1
    fi
}

trap 'echo -e "\n${RED}❌ Deployment interrupted${NC}"; exit 1' INT TERM

main "$@"
