#!/usr/bin/env bash
set -euo pipefail

# Fix Missing Components Script
# This script fixes missing components without running a full deployment

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
: "${SYSTEM_USER:=${SUDO_USER:-$(who am i | awk '{print $1}')}}"

echo -e "${BLUE}🔧 Fixing Missing Components${NC}"
echo "=================================="

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}❌ Please run as root: sudo $0${NC}" >&2
        exit 1
    fi
}

# Function to install CUDA toolkit
install_cuda() {
    echo -e "${BLUE}🔄 Installing CUDA toolkit...${NC}"
    
    if ! command -v nvcc >/dev/null 2>&1; then
        apt update
        if apt install -y cuda-toolkit-12-9; then
            echo -e "${GREEN}✅ CUDA toolkit installed${NC}"
            
            # Set up CUDA environment variables
            if ! grep -q "CUDA_HOME" /etc/environment; then
                echo "CUDA_HOME=/usr/local/cuda-12.9" >> /etc/environment
                echo "PATH=\$PATH:/usr/local/cuda-12.9/bin" >> /etc/environment
                echo "LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:/usr/local/cuda-12.9/lib64" >> /etc/environment
                echo -e "${GREEN}✅ CUDA environment variables configured${NC}"
            fi
            
            # Create symlinks for easier access
            ln -sf /usr/local/cuda-12.9/bin/nvcc /usr/local/bin/nvcc
            ln -sf /usr/local/cuda-12.9/bin/nvidia-smi /usr/local/bin/nvidia-smi
            
            echo -e "${GREEN}✅ CUDA toolkit setup complete${NC}"
        else
            echo -e "${RED}❌ Failed to install CUDA toolkit${NC}"
            return 1
        fi
    else
        echo -e "${GREEN}✅ CUDA toolkit already installed${NC}"
    fi
}

# Function to create AI directories
create_ai_directories() {
    echo -e "${BLUE}🔄 Creating AI directories...${NC}"
    
    local ai_dirs=(
        "/opt/ai"
        "/opt/ai/models"
        "/opt/ai/huggingface"
        "/opt/ai/transformers"
        "/opt/ai/datasets"
    )
    
    for dir in "${ai_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            chown "$SYSTEM_USER:$SYSTEM_USER" "$dir"
            echo -e "${GREEN}✅ Created: $dir${NC}"
        else
            echo -e "${GREEN}✅ Exists: $dir${NC}"
        fi
    done
}

# Function to install AI libraries
install_ai_libraries() {
    echo -e "${BLUE}🔄 Installing AI libraries...${NC}"
    
    # Add user's local bin to PATH
    if ! grep -q ".local/bin" "/home/$SYSTEM_USER/.bashrc"; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "/home/$SYSTEM_USER/.bashrc"
        echo -e "${GREEN}✅ Added .local/bin to PATH${NC}"
    fi
    
    # Install PyTorch with CUDA support
    if ! python3 -c "import torch" 2>/dev/null; then
        echo -e "${BLUE}🔄 Installing PyTorch...${NC}"
        sudo -u "$SYSTEM_USER" pip3 install --break-system-packages --no-warn-script-location torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
        echo -e "${GREEN}✅ PyTorch installed${NC}"
    else
        echo -e "${GREEN}✅ PyTorch already installed${NC}"
    fi
    
    # Install TensorFlow
    if ! python3 -c "import tensorflow" 2>/dev/null; then
        echo -e "${BLUE}🔄 Installing TensorFlow...${NC}"
        sudo -u "$SYSTEM_USER" pip3 install --break-system-packages --no-warn-script-location tensorflow
        echo -e "${GREEN}✅ TensorFlow installed${NC}"
    else
        echo -e "${GREEN}✅ TensorFlow already installed${NC}"
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
            echo -e "${BLUE}🔄 Installing $lib...${NC}"
            sudo -u "$SYSTEM_USER" pip3 install --break-system-packages --no-warn-script-location "$lib"
            echo -e "${GREEN}✅ $lib installed${NC}"
        else
            echo -e "${GREEN}✅ $lib already installed${NC}"
        fi
    done
}

# Function to set CPU performance mode
set_performance_mode() {
    echo -e "${BLUE}🔄 Setting CPU performance mode...${NC}"
    
    if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]]; then
        echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1
        
        # Make it persistent across reboots
        if ! grep -q "cpufreq" /etc/default/grub; then
            sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="cpufreq.default_governor=performance /' /etc/default/grub
            update-grub
        fi
        echo -e "${GREEN}✅ CPU performance mode set${NC}"
    else
        echo -e "${YELLOW}⚠️  CPU governor not available${NC}"
    fi
}

# Main function
main() {
    check_root
    
    install_cuda
    create_ai_directories
    install_ai_libraries
    set_performance_mode
    
    echo -e "${GREEN}🎉 All missing components fixed!${NC}"
    echo -e "${BLUE}💡 Run './scripts/verify.sh' to check the results${NC}"
}

# Run main function
main "$@" 