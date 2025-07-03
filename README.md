# Odin's AI Platform

A complete, production-ready AI/ML platform with GPU support, monitoring, and development tools.

## 🚀 Features

- **Full-Stack AI Platform**: Complete environment for AI/ML development and deployment
- **GPU Support**: Optimized for NVIDIA GPUs with CUDA 12.8 and PyTorch/TensorFlow
- **Jupyter Lab**: Interactive development environment with GPU acceleration
- **Monitoring**: Prometheus, Grafana, and Node Exporter with pre-configured data sources
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

### 🚀 Performance Expectations

**Build Times** (based on RTX 5090 + Ryzen 9 9950X + 128GB RAM):
- **Initial deployment**: ~4-5 minutes
- **Docker image build**: ~3-4 minutes
- **Service startup**: ~1-2 minutes
- **Jupyter Lab ready**: ~2-3 minutes after deployment

**Hardware Recommendations**:
- **Minimum**: 8GB RAM, any modern CPU, 50GB storage
- **Recommended**: 16GB+ RAM, 6+ core CPU, SSD storage
- **Optimal**: 32GB+ RAM, 8+ core CPU, RTX 4090+ GPU, NVMe storage
- **Production**: 64GB+ RAM, 12+ core CPU, multiple GPUs, enterprise storage

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
- **prometheus**: Metrics collection and storage
- **grafana**: Monitoring visualization (with pre-configured datasources)
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

### Performance Benchmarks

**Expected Performance** (RTX 5090 + Ryzen 9 9950X + 128GB RAM):

**Training**:
- **Small models** (< 1B parameters): Real-time training
- **Medium models** (1-7B parameters): Fast training with full precision
- **Large models** (7-70B parameters): Efficient training with mixed precision
- **XL models** (> 70B parameters): Possible with model parallelism

**Inference**:
- **Batch inference**: 1000+ samples/second for most models
- **Real-time inference**: < 100ms latency for standard models
- **Large model inference**: 1-5 seconds for 70B+ parameter models

**Memory Usage**:
- **Jupyter Lab**: 2-4GB RAM typical usage
- **Model serving**: 4-16GB RAM depending on model size
- **GPU VRAM**: 8-24GB depending on model and batch size

### Custom Jupyter Notebooks

Access Jupyter Lab at http://localhost:8888 and create new notebooks. All Python packages are pre-installed.

### API Development

The main application is built with FastAPI. Modify `app/main.py` to add new endpoints.

## 📊 Monitoring

### Grafana Dashboards

Access Grafana at http://localhost:3001 with credentials `admin/admin`. The platform includes:

- **Pre-configured Prometheus datasource** for metrics collection
- **Basic monitoring infrastructure** ready for dashboard creation
- **System metrics** available from Node Exporter
- **Container metrics** from Docker
- **Application metrics** from the main application

**Note**: While the monitoring infrastructure is pre-configured, you'll need to create custom dashboards in Grafana to visualize the metrics. The platform provides the data sources and metrics collection, but dashboard creation is left to the user.

### GPU Monitoring

The platform includes real-time GPU monitoring accessible at http://localhost:8080/gpu.

**GPU Performance Notes**:
- **RTX 5090**: Full CUDA 12.8 support with 32GB VRAM for large models
- **RTX 4090/4080**: Excellent performance for most AI workloads
- **RTX 3090/3080**: Good performance, may need model optimization for very large models
- **GTX 1660+**: Basic support, suitable for smaller models and inference
- **No GPU**: CPU-only mode available but significantly slower for training

## ✅ Verification & Troubleshooting

Odin's AI Platform now uses a Docker-focused verification workflow. Here's how to check your deployment:

### 1. Docker Verification (no sudo required)
```bash
./scripts/verify-docker.sh
```
- Checks all containers, endpoints, GPU access, databases, and AI frameworks.
- Should show 100% pass if all services are healthy.

### 2. GPU Verification
```bash
./scripts/verify-ai-gpu.sh
```
- Checks PyTorch and TensorFlow GPU access in both main and Jupyter containers.
- **Note:** You may see a warning about CUDA arch support for new GPUs (e.g., RTX 5090). This does not affect basic functionality and will be resolved in future PyTorch releases.

### 3. Jupyter GPU Verification
```bash
./scripts/verify-jupyter.sh
```
- Runs a full suite of GPU tests inside the Jupyter container.
- All tests should pass if GPU is available and drivers are correct.

### 4. Service Verification
```bash
cd docker
../scripts/verify-services.sh
```
- Must be run from the `docker` directory.
- Checks all service endpoints and container health.

### 5. Status & Troubleshooting
```bash
./scripts/status.sh
sudo ./scripts/troubleshoot.sh  # (if needed, requires root)
```

---

## 🛠️ Useful Commands

```bash
# Check system status
./scripts/status.sh

# Run Docker verification tests (no sudo required)
./scripts/verify-docker.sh

# Run GPU verification
./scripts/verify-ai-gpu.sh

# Run Jupyter GPU verification
./scripts/verify-jupyter.sh

# Run service verification (from docker directory)
cd docker && ../scripts/verify-services.sh

# Troubleshoot issues (requires sudo)
sudo ./scripts/troubleshoot.sh
```

---

## ⚠️ Notes
- The old `verify.sh` script for bare-metal checks has been removed. All verification is now Docker/container focused.
- PyTorch may show a warning about CUDA arch support for the latest GPUs (e.g., RTX 5090). This is expected and does not affect most workflows.
- Always run `verify-services.sh` from the `docker` directory.
- For best results, ensure all containers are healthy and endpoints are accessible as shown in the verification scripts.

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
