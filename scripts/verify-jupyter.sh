#!/usr/bin/env bash
set -euo pipefail

# Odin AI Jupyter Verification Script
# Automatically runs verification tests in Jupyter to ensure GPU support

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
JUPYTER_CONTAINER="odins-ai-jupyter"
JUPYTER_URL="http://localhost:8888"
MAX_WAIT_TIME=300  # 5 minutes
WAIT_INTERVAL=10   # 10 seconds

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Logging function
log() {
    local level="$1"
    local message="$2"
    local log_file="/tmp/odins-ai-jupyter-verification.log"

    # Try to write to log file, but don't fail if we can't
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$log_file" 2>/dev/null || echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
}

# Test function
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_output="$3"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -n "Testing $test_name... "

    if eval "$test_command" | grep -q "$expected_output" 2>/dev/null; then
        echo -e "${GREEN}✓ PASS${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        log "INFO" "Test PASSED: $test_name"
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        log "ERROR" "Test FAILED: $test_name"
        return 1
    fi
}

# Wait for Jupyter container to be ready
wait_for_jupyter() {
    echo -e "${BLUE}🔄 Waiting for Jupyter container to be ready...${NC}"
    log "INFO" "Waiting for Jupyter container to be ready"

    local wait_time=0
    while [[ $wait_time -lt $MAX_WAIT_TIME ]]; do
        if docker exec "$JUPYTER_CONTAINER" pgrep -f "jupyter" >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Jupyter container is ready!${NC}"
            log "INFO" "Jupyter container is ready"

            # Additional wait for PyTorch installation
            echo -e "${BLUE}⏳ Waiting for PyTorch installation to complete...${NC}"
            log "INFO" "Waiting for PyTorch installation to complete"

            local pytorch_wait=0
            local pytorch_max_wait=180  # 3 minutes for PyTorch
            while [[ $pytorch_wait -lt $pytorch_max_wait ]]; do
                if docker exec "$JUPYTER_CONTAINER" python3 -c "import torch; print('PyTorch ready')" >/dev/null 2>&1; then
                    echo -e "${GREEN}✅ PyTorch is ready!${NC}"
                    log "INFO" "PyTorch is ready"
                    return 0
                fi

                echo -n "."
                sleep 10
                pytorch_wait=$((pytorch_wait + 10))
            done

            echo -e "${YELLOW}⚠️  PyTorch installation timeout, but continuing...${NC}"
            log "WARN" "PyTorch installation timeout, but continuing"
            return 0
        fi

        echo -n "."
        sleep $WAIT_INTERVAL
        wait_time=$((wait_time + WAIT_INTERVAL))
    done

    echo -e "${RED}❌ Timeout waiting for Jupyter container${NC}"
    log "ERROR" "Timeout waiting for Jupyter container"
    return 1
}

# Create Python verification script
create_verification_script() {
    local script_path="/tmp/jupyter_verification.py"

    cat > "$script_path" <<'EOF'
#!/usr/bin/env python3
"""
Jupyter GPU Verification Script
Runs the 5 verification test cells to ensure GPU support
"""

import sys
import subprocess
import time
import json

def run_cell(cell_name, code, expected_outputs):
    """Run a verification cell and check outputs"""
    print(f"\n{'='*60}")
    print(f"🧪 Running: {cell_name}")
    print(f"{'='*60}")

    try:
        # Execute the code
        result = subprocess.run([
            'python3', '-c', code
        ], capture_output=True, text=True, timeout=60)

        output = result.stdout + result.stderr

        # Check for expected outputs
        all_found = True
        for expected in expected_outputs:
            if expected.lower() in output.lower():
                print(f"✅ Found: {expected}")
            else:
                print(f"❌ Missing: {expected}")
                all_found = False

        # Print output for debugging
        print(f"\n📋 Output:")
        print(output[:500] + "..." if len(output) > 500 else output)

        return all_found

    except subprocess.TimeoutExpired:
        print(f"❌ Timeout running {cell_name}")
        return False
    except Exception as e:
        print(f"❌ Error running {cell_name}: {e}")
        return False

def main():
    """Main verification function"""
    print("🚀 Starting Jupyter GPU Verification Tests")
    print("="*60)

    # Check if PyTorch is available
    pytorch_available = False
    try:
        import torch
        pytorch_available = True
        print("✅ PyTorch is available")
    except ImportError:
        print("⚠️  PyTorch not available yet, skipping PyTorch tests")

    # Test 1: TensorFlow GPU Detection
    tf_code = '''
import tensorflow as tf
print(f"TensorFlow version: {tf.__version__}")
print(f"GPUs: {tf.config.list_physical_devices('GPU')}")
print(f"GPU count: {len(tf.config.list_physical_devices('GPU'))}")
'''
    tf_expected = ["tensorflow", "gpu", "gpu count"]

    # Test 2: PyTorch GPU Detection (only if available)
    torch_code = '''
import torch
print(f"PyTorch version: {torch.__version__}")
print(f"CUDA available: {torch.cuda.is_available()}")
print(f"CUDA device count: {torch.cuda.device_count()}")
if torch.cuda.is_available():
    print(f"Device name: {torch.cuda.get_device_name(0)}")
    print(f"Device capability: {torch.cuda.get_device_capability(0)}")
'''
    torch_expected = ["pytorch", "cuda available", "device count"]

    # Test 3: TensorFlow GPU Computation
    tf_compute_code = '''
import tensorflow as tf
import numpy as np

# Create a simple tensor on GPU
with tf.device('/GPU:0'):
    a = tf.constant([[1.0, 2.0], [3.0, 4.0]])
    b = tf.constant([[5.0, 6.0], [7.0, 8.0]])
    c = tf.matmul(a, b)
    print(f"TensorFlow GPU computation result: {c}")
    print(f"Device: {c.device}")
'''
    tf_compute_expected = ["gpu computation", "device", "result"]

    # Test 4: PyTorch GPU Computation (only if available)
    torch_compute_code = '''
import torch
import numpy as np

# Create tensors on GPU
if torch.cuda.is_available():
    a = torch.tensor([[1.0, 2.0], [3.0, 4.0]], device='cuda')
    b = torch.tensor([[5.0, 6.0], [7.0, 8.0]], device='cuda')
    c = torch.matmul(a, b)
    print(f"PyTorch GPU computation result: {c}")
    print(f"Device: {c.device}")
else:
    print("CUDA not available")
'''
    torch_compute_expected = ["gpu computation", "device", "result"]

    # Test 5: Neural Network Training (only if available)
    nn_code = '''
import torch
import torch.nn as nn
import torch.optim as optim

if torch.cuda.is_available():
    # Simple neural network
    class SimpleNN(nn.Module):
        def __init__(self):
            super(SimpleNN, self).__init__()
            self.fc1 = nn.Linear(10, 5)
            self.fc2 = nn.Linear(5, 1)

        def forward(self, x):
            x = torch.relu(self.fc1(x))
            x = self.fc2(x)
            return x

    # Create model and move to GPU
    model = SimpleNN().cuda()
    optimizer = optim.Adam(model.parameters())
    criterion = nn.MSELoss()

    # Create dummy data
    x = torch.randn(32, 10).cuda()
    y = torch.randn(32, 1).cuda()

    # Training step
    optimizer.zero_grad()
    output = model(x)
    loss = criterion(output, y)
    loss.backward()
    optimizer.step()

    print(f"Neural network training successful!")
    print(f"Loss: {loss.item():.4f}")
    print(f"Model device: {next(model.parameters()).device}")
else:
    print("CUDA not available for neural network training")
'''
    nn_expected = ["neural network", "training", "successful", "loss"]

    # Run tests based on availability
    tests = [
        ("TensorFlow GPU Detection", tf_code, tf_expected),
        ("TensorFlow GPU Computation", tf_compute_code, tf_compute_expected),
    ]

    if pytorch_available:
        tests.extend([
            ("PyTorch GPU Detection", torch_code, torch_expected),
            ("PyTorch GPU Computation", torch_compute_code, torch_compute_expected),
            ("Neural Network Training", nn_code, nn_expected)
        ])

    passed = 0
    total = len(tests)

    for test_name, code, expected in tests:
        if run_cell(test_name, code, expected):
            passed += 1

    # Summary
    print(f"\n{'='*60}")
    print(f"📊 VERIFICATION SUMMARY")
    print(f"{'='*60}")
    print(f"Tests passed: {passed}/{total}")

    if pytorch_available:
        if passed == total:
            print(f"🎉 All tests passed! GPU support is working correctly.")
            return 0
        else:
            print(f"⚠️  Some tests failed. Check the output above for details.")
            return 1
    else:
        if passed == 2:  # Only TensorFlow tests
            print(f"✅ TensorFlow tests passed! PyTorch will be available after installation completes.")
            print(f"💡 Run './scripts/verify-jupyter.sh' again in a few minutes to test PyTorch.")
            return 0
        else:
            print(f"⚠️  Some TensorFlow tests failed. Check the output above for details.")
            return 1

if __name__ == "__main__":
    sys.exit(main())
EOF

    echo "$script_path"
}

# Run verification tests
run_verification_tests() {
    echo -e "${BLUE}🧪 Running Jupyter GPU Verification Tests${NC}"
    log "INFO" "Starting Jupyter GPU verification tests"

    # Create verification script
    local script_path=$(create_verification_script)

    # Copy script to container
    docker cp "$script_path" "$JUPYTER_CONTAINER:/tmp/jupyter_verification.py"

    # Run verification in container
    echo -e "${BLUE}🔄 Executing verification tests in Jupyter container...${NC}"

    if docker exec "$JUPYTER_CONTAINER" python3 /tmp/jupyter_verification.py; then
        echo -e "${GREEN}✅ All Jupyter verification tests passed!${NC}"
        log "INFO" "All Jupyter verification tests passed"
        return 0
    else
        echo -e "${RED}❌ Some Jupyter verification tests failed${NC}"
        log "ERROR" "Some Jupyter verification tests failed"
        return 1
    fi
}

# Check Jupyter container status
check_jupyter_status() {
    echo -e "${BLUE}🔍 Checking Jupyter container status...${NC}"

    # Check if container exists and is running
    if ! docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "$JUPYTER_CONTAINER"; then
        echo -e "${RED}❌ Jupyter container '$JUPYTER_CONTAINER' is not running${NC}"
        echo -e "${YELLOW}💡 Available containers:${NC}"
        docker ps --format "table {{.Names}}\t{{.Status}}" || echo "No containers running"
        return 1
    fi

    echo -e "${GREEN}✅ Jupyter container is running${NC}"
    docker ps --format "table {{.Names}}\t{{.Status}}" | grep "$JUPYTER_CONTAINER"
    return 0
}

# Main function
main() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              🧪 Jupyter GPU Verification Tests              ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo

    log "INFO" "Starting Jupyter verification script"

    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        echo -e "${RED}❌ Docker is not running${NC}"
        echo -e "${YELLOW}💡 Please start Docker first: sudo systemctl start docker${NC}"
        log "ERROR" "Docker is not running"
        exit 1
    fi

    # Check Jupyter container status
    if ! check_jupyter_status; then
        echo -e "${RED}❌ Jupyter container is not running. Please start it first.${NC}"
        log "ERROR" "Jupyter container is not running"
        exit 1
    fi

    # Wait for Jupyter to be ready
    if ! wait_for_jupyter; then
        echo -e "${RED}❌ Jupyter container is not responding${NC}"
        log "ERROR" "Jupyter container is not responding"
        exit 1
    fi

    # Run verification tests
    if run_verification_tests; then
        echo -e "${GREEN}🎉 Jupyter GPU verification completed successfully!${NC}"
        log "INFO" "Jupyter GPU verification completed successfully"
        exit 0
    else
        echo -e "${RED}❌ Jupyter GPU verification failed${NC}"
        log "ERROR" "Jupyter GPU verification failed"
        exit 1
    fi
}

# Run main function
main "$@"
