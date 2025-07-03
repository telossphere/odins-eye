# Odin's AI Docker Image
# Based on PyTorch nightly with CUDA 12.8 and cuDNN 9 for full RTX 5090 (Blackwell) support
# See: https://pytorch.org/get-started/locally/ for latest tags

FROM pytorch/pytorch:2.7.1-cuda12.8-cudnn9-runtime

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=America/New_York
ENV PYTHONUNBUFFERED=1
ENV CUDA_VISIBLE_DEVICES=0
ENV TF_FORCE_GPU_ALLOW_GROWTH=true
ENV PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:128

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl wget git gnupg ca-certificates unzip lsb-release \
    build-essential dkms htop neofetch tmux net-tools pciutils \
    software-properties-common apt-transport-https \
    python3-dev \
    libblas-dev liblapack-dev libatlas-base-dev \
    libhdf5-dev libhdf5-serial-dev \
    libjpeg-dev libpng-dev libtiff-dev \
    libavcodec-dev libavformat-dev libswscale-dev \
    libv4l-dev libxvidcore-dev libx264-dev \
    libgtk-3-dev libcanberra-gtk3-module \
    libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
    jq tree ncdu iotop nethogs speedtest-cli ffmpeg imagemagick \
    && rm -rf /var/lib/apt/lists/*

# Install NVIDIA utilities for GPU monitoring
RUN apt-get update && apt-get install -y --no-install-recommends \
    nvidia-utils-535 \
    && rm -rf /var/lib/apt/lists/*

# Install Docker CLI
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && apt-get install -y --no-install-recommends docker-ce-cli && rm -rf /var/lib/apt/lists/*

# Create application user with correct UID/GID to match host
RUN groupadd -g 988 docker && \
    useradd -m -s /bin/bash -u 1000 -g 988 odin && \
    mkdir -p /opt/odins-eye /opt/ai/models /opt/ai/huggingface /var/log/odins-eye && \
    chown -R odin:docker /opt/odins-eye /opt/ai /var/log/odins-eye

# Set working directory
WORKDIR /opt/odins-eye

# Copy application files
COPY --chown=odin:odin . /opt/odins-eye/

# Create necessary directories and set permissions
RUN mkdir -p /opt/odins-eye/{logs,config,models} && \
    chown -R odin:docker /opt/odins-eye

# Install additional Python dependencies for the AI application
# Using the exact versions from the working deployment
RUN pip install --no-cache-dir \
    flask==3.1.1 fastapi==0.115.14 uvicorn==0.35.0 \
    numpy==2.1.3 pandas==2.3.0 matplotlib==3.10.3 \
    requests aiohttp==3.12.13 \
    pillow==11.0.0 opencv-python==4.11.0.86 \
    tqdm rich==14.0.0 click \
    psutil jinja2 \
    jupyterlab==4.4.4 jupyter==1.1.1 \
    tensorflow==2.19.0 \
    scikit-learn==1.7.0 scipy==1.16.0 \
    transformers==4.53.0 datasets==3.6.0 \
    accelerate==1.8.1

# Switch to application user
USER odin

# Expose ports
EXPOSE 8080 3000 3001 3002 8888

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python3 -c "print('Container is healthy')" || exit 1

# Default command - start the AI application
CMD ["python3", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
