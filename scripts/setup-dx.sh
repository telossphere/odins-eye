#!/bin/bash

# Odin's Eye Platform - Developer Experience Setup Script
# Installs all linting, formatting, and development tools

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Setting up Developer Experience Tools${NC}"
echo "============================================="

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install Python package if not exists
install_python_package() {
    local package=$1
    local name=${2:-$1}

    echo -n "Checking $name... "
    if python3 -c "import $package" 2>/dev/null; then
        echo -e "${GREEN}✓ Already installed${NC}"
    else
        echo -e "${YELLOW}Installing...${NC}"
        # Try pipx first (recommended for Ubuntu 24.04+)
        if command_exists pipx; then
            pipx install "$package"
            echo -e "${GREEN}✓ Installed $name via pipx${NC}"
        else
            # Fallback to pip with --break-system-packages (not recommended but works)
            pip3 install --user --break-system-packages "$package"
            echo -e "${GREEN}✓ Installed $name via pip${NC}"
        fi
    fi
}

# Function to install system package
install_system_package() {
    local package=$1
    local name=${2:-$1}

    echo -n "Checking $name... "
    if command_exists "$package"; then
        echo -e "${GREEN}✓ Already installed${NC}"
    else
        echo -e "${YELLOW}Installing...${NC}"
        if command_exists apt-get; then
            sudo apt-get update && sudo apt-get install -y "$package"
        elif command_exists yum; then
            sudo yum install -y "$package"
        elif command_exists brew; then
            brew install "$package"
        else
            echo -e "${RED}✗ No package manager found${NC}"
            return 1
        fi
        echo -e "${GREEN}✓ Installed $name${NC}"
    fi
}

echo -e "\n${BLUE}📦 Installing Python Development Tools${NC}"
echo "----------------------------------------"

# Install pipx if not available (recommended for Ubuntu 24.04+)
if ! command_exists pipx; then
    echo -n "Installing pipx... "
    if command_exists apt-get; then
        sudo apt-get update && sudo apt-get install -y pipx
        pipx ensurepath
        echo -e "${GREEN}✓ Installed pipx${NC}"
    else
        echo -e "${YELLOW}⚠ pipx not available, will use pip fallback${NC}"
    fi
fi

# Install Python development tools
install_python_package "black" "Black (code formatter)"
install_python_package "isort" "isort (import sorter)"
install_python_package "flake8" "Flake8 (linter)"
install_python_package "mypy" "MyPy (type checker)"
install_python_package "pre_commit" "Pre-commit (git hooks)"

echo -e "\n${BLUE}🔧 Installing System Tools${NC}"
echo "----------------------------"

# Install system tools
install_system_package "shellcheck" "ShellCheck (shell script linter)"

# Install hadolint manually (not in Ubuntu repos)
echo -n "Checking Hadolint (Dockerfile linter)... "
if command_exists hadolint; then
    echo -e "${GREEN}✓ Already installed${NC}"
else
    echo -e "${YELLOW}Installing...${NC}"
    # Download and install hadolint
    HADOLINT_VERSION="v2.12.0"
    curl -sSfL https://github.com/hadolint/hadolint/releases/download/${HADOLINT_VERSION}/hadolint-Linux-x86_64 -o /tmp/hadolint
    chmod +x /tmp/hadolint
    sudo mv /tmp/hadolint /usr/local/bin/hadolint
    echo -e "${GREEN}✓ Installed Hadolint${NC}"
fi

echo -e "\n${BLUE}⚙️  Setting up Pre-commit Hooks${NC}"
echo "--------------------------------"

# Setup pre-commit hooks
if command_exists pre-commit; then
    echo -n "Installing pre-commit hooks... "
    pre-commit install
    echo -e "${GREEN}✓ Pre-commit hooks installed${NC}"
else
    echo -e "${YELLOW}⚠ Pre-commit not available, skipping hooks${NC}"
fi

echo -e "\n${BLUE}🧪 Testing Installation${NC}"
echo "------------------------"

# Test installations
echo -n "Testing Black... "
if command_exists black; then
    echo -e "${GREEN}✓ Working${NC}"
else
    echo -e "${RED}✗ Not found${NC}"
fi

echo -n "Testing isort... "
if command_exists isort; then
    echo -e "${GREEN}✓ Working${NC}"
else
    echo -e "${RED}✗ Not found${NC}"
fi

echo -n "Testing flake8... "
if command_exists flake8; then
    echo -e "${GREEN}✓ Working${NC}"
else
    echo -e "${RED}✗ Not found${NC}"
fi

echo -n "Testing ShellCheck... "
if command_exists shellcheck; then
    echo -e "${GREEN}✓ Working${NC}"
else
    echo -e "${RED}✗ Not found${NC}"
fi

echo -n "Testing Hadolint... "
if command_exists hadolint; then
    echo -e "${GREEN}✓ Working${NC}"
else
    echo -e "${RED}✗ Not found${NC}"
fi

echo -e "\n${BLUE}📋 Available Commands${NC}"
echo "----------------------"
echo -e "${GREEN}Format Python code:${NC} black ."
echo -e "${GREEN}Sort imports:${NC} isort ."
echo -e "${GREEN}Lint Python:${NC} flake8 ."
echo -e "${GREEN}Type check:${NC} mypy ."
echo -e "${GREEN}Lint shell scripts:${NC} shellcheck scripts/*.sh"
echo -e "${GREEN}Lint Dockerfiles:${NC} hadolint docker/Dockerfile"
echo -e "${GREEN}Run all checks:${NC} pre-commit run --all-files"

echo -e "\n${GREEN}🎉 Developer Experience setup complete!${NC}"
echo -e "${YELLOW}💡 Tip: VS Code will automatically install recommended extensions when you open this workspace.${NC}"
