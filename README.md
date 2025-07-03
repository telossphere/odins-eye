# Odin's AI Platform

A complete, production-ready AI/ML platform with GPU support, monitoring, and development tools.

## 🚀 Features

- **Full-Stack AI Platform**: Complete environment for AI/ML development and deployment
- **GPU Support**: Optimized for NVIDIA GPUs with CUDA 12.8 and PyTorch/TensorFlow
- **Jupyter Lab**: Interactive development environment with GPU acceleration
- **Monitoring**: Prometheus, Grafana, and Node Exporter for system monitoring
- **Database**: PostgreSQL for persistent storage
- **Caching**: Redis for high-performance caching
- **Reverse Proxy**: Nginx for secure HTTP routing
- **One-Command Deployment**: Simple deployment script for easy setup

## 🛠️ Requirements

- **OS**: Ubuntu 22.04+ (tested on Ubuntu 24.04)
- **Docker**: Docker Engine 24.0+ with Docker Compose
- **GPU**: NVIDIA GPU with CUDA support (optional but recommended)
- **RAM**: 8GB+ (16GB+ recommended)
- **Storage**: 50GB+ available space

## 📦 Quick Start

1. **Clone or download this package**
   ```bash
   git clone <repository-url>
   cd odins-ai-platform-v1.0.0
   ```

2. **Deploy the platform**
   ```bash
   ./deploy.sh
   ```

3. **Access the services**
   - Main Dashboard: http://localhost:8080
   - Jupyter Lab: http://localhost:8888
   - Grafana: http://localhost:3001 (admin/admin)
   - GPU Monitor: http://localhost:8080/gpu

## 🏗️ Architecture

The platform consists of the following services:

- **odins-ai**: Main FastAPI application with web dashboard
- **jupyter**: Jupyter Lab for interactive development
- **postgres**: PostgreSQL database
- **redis**: Redis cache
- **prometheus**: Metrics collection
- **grafana**: Monitoring dashboards
- **node-exporter**: System metrics
- **nginx**: Reverse proxy

## 🔧 Configuration

### Environment Variables

Key environment variables can be set in the `docker-compose.yml`:

- `POSTGRES_PASSWORD`: Database password
- `GRAFANA_PASSWORD`: Grafana admin password
- `CUDA_VISIBLE_DEVICES`: GPU device selection

### Volumes

The platform uses Docker volumes for persistent data:

- `./data/postgres`: Database files
- `./data/redis`: Redis data
- `./data/prometheus`: Metrics data
- `./data/grafana`: Grafana dashboards
- `./logs`: Application logs
- `./models`: AI model storage

## 🧪 Development

### Adding Custom Models

Place your AI models in the `./models` directory. They will be automatically available to the containers.

### Custom Jupyter Notebooks

Access Jupyter Lab at http://localhost:8888 and create new notebooks. All Python packages are pre-installed.

### API Development

The main application is built with FastAPI. Modify `app/main.py` to add new endpoints.

## 📊 Monitoring

### Grafana Dashboards

Access Grafana at http://localhost:3001 with credentials `admin/admin`. Pre-configured dashboards include:

- System metrics
- GPU utilization
- Container performance
- Application metrics

### GPU Monitoring

The platform includes real-time GPU monitoring accessible at http://localhost:8080/gpu.

## 🔍 Troubleshooting

### Common Issues

1. **GPU not detected**
   - Ensure NVIDIA drivers are installed
   - Check NVIDIA Container Toolkit installation
   - Run `nvidia-smi` to verify GPU access

2. **Services not starting**
   - Check Docker logs: `cd docker && docker compose logs`
   - Verify port availability
   - Check system resources

3. **Performance issues**
   - Monitor GPU temperature and utilization
   - Check system memory usage
   - Verify CUDA installation

### Useful Commands

```bash
# Check system status
./scripts/status.sh

# Run verification tests
./scripts/verify.sh

# Troubleshoot issues
./scripts/troubleshoot.sh

# View service logs
cd docker && docker compose logs -f

# Restart services
cd docker && docker compose restart

# Stop all services
cd docker && docker compose down
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- **FastAPI** for the web framework
- **Jupyter** for the development environment
- **Docker** for containerization
- **NVIDIA** for GPU support
- **The open-source community** for all the amazing tools

---

**Made with ❤️ for the AI/ML community**
