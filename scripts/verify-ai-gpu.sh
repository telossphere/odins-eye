#!/bin/bash
set -e

# Test PyTorch in main app
printf '\n[PyTorch in main app]\n'
docker exec -it odins-eye python3 -c "import torch; print(torch.__version__); print(torch.cuda.is_available()); print(torch.cuda.get_device_name(0))"

# Test TensorFlow and PyTorch in Jupyter
printf '\n[TensorFlow & PyTorch in Jupyter]\n'
docker exec -it odins-eye-jupyter python -c "import tensorflow as tf; print(tf.__version__, tf.config.list_physical_devices('GPU'))"
docker exec -it odins-eye-jupyter python -c "import torch; print(torch.__version__); print(torch.cuda.is_available()); print(torch.cuda.get_device_name(0))"
