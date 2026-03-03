#!/bin/bash
# Fix for Ubuntu 24.04 (Noble)

set -e

echo "Fixing NVIDIA Container Toolkit for Ubuntu 24.04..."

# Method 1: Use existing CUDA repo (if available)
if grep -q "cuda/repos/ubuntu2404" /etc/apt/sources.list.d/* 2>/dev/null; then
    echo "CUDA repo found, installing nvidia-container-toolkit..."
    apt-get update
    apt-get install -y nvidia-container-toolkit
else
    # Method 2: Use libnvidia-container repo
    echo "Adding libnvidia-container repository..."
    
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    
    curl -s -L https://nvidia.github.io/libnvidia-container/gpgkey | \
        gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    
    apt-get update
    apt-get install -y nvidia-container-toolkit
fi

# Configure Docker
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker

echo "✅ NVIDIA Container Toolkit installed!"
docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi
