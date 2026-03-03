#!/bin/bash
#
# Ollama Model Manager - Flexible Installer
# Usage: curl -fsSL ... | bash -s [OPTION]
#
# Options:
#   ollama-only    - Deploy Ollama only (no manager UI)
#   full           - Deploy Ollama + Manager UI (default)
#

set -e

# Parse option
DEPLOY_MODE="${1:-full}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Detect GPU
detect_gpu() {
    log "Detecting GPU..."
    GPU_TYPE="cpu"
    
    if command -v nvidia-smi &> /dev/null; then
        if nvidia-smi &> /dev/null; then
            GPU_TYPE="nvidia"
            GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
            success "NVIDIA GPU detected: $GPU_MODEL"
        fi
    fi
    
    if [ "$GPU_TYPE" = "cpu" ]; then
        warn "No GPU detected - using CPU mode"
    fi
}

# Install Docker
install_docker() {
    if ! command -v docker &> /dev/null; then
        log "Installing Docker..."
        curl -fsSL https://get.docker.com | sh
        systemctl start docker 2>/dev/null || true
        success "Docker installed"
    fi
}

# Install NVIDIA Container Toolkit
install_nvidia_docker() {
    if [ "$GPU_TYPE" = "nvidia" ]; then
        log "Installing NVIDIA Container Toolkit..."
        distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
        curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add - 2>/dev/null || true
        curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | tee /etc/apt/sources.list.d/nvidia-docker.list
        apt-get update
        apt-get install -y nvidia-docker2
        systemctl restart docker
        success "NVIDIA Container Toolkit installed"
    fi
}

# Deploy Ollama Only
deploy_ollama_only() {
    log "Deploying Ollama Only..."
    
    # Create compose file
    cat > /opt/ollama/docker-compose.yml << EOF
version: '3.8'

services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    ports:
      - "11434:11434"
    volumes:
      - ollama_data:/root/.ollama
    environment:
      - OLLAMA_HOST=0.0.0.0
      - OLLAMA_ORIGINS=*
EOF

    # Add GPU config if NVIDIA
    if [ "$GPU_TYPE" = "nvidia" ]; then
        cat >> /opt/ollama/docker-compose.yml << 'EOF'
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
EOF
    fi

    # Add volume
    cat >> /opt/ollama/docker-compose.yml << 'EOF'

volumes:
  ollama_data:
EOF

    # Start
    cd /opt/ollama
    docker-compose up -d
    
    success "Ollama deployed!"
    echo ""
    echo "API: http://$(curl -s ifconfig.me 2>/dev/null || echo 'localhost'):11434"
}

# Deploy Full Stack (Ollama + Manager)
deploy_full() {
    log "Deploying Ollama + Model Manager..."
    
    mkdir -p /opt/ollama-manager
    cd /opt/ollama-manager
    
    # Create compose file
    cat > docker-compose.yml << EOF
version: '3.8'

services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    ports:
      - "11434:11434"
    volumes:
      - ollama_data:/root/.ollama
    environment:
      - OLLAMA_HOST=0.0.0.0
      - OLLAMA_ORIGINS=*
EOF

    # Add GPU config if NVIDIA
    if [ "$GPU_TYPE" = "nvidia" ]; then
        cat >> docker-compose.yml << 'EOF'
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
EOF
    fi

    # Add Manager service
    cat >> docker-compose.yml << 'EOF'

  manager:
    image: n00n0i/ollama-model-manager:latest
    container_name: ollama-manager
    restart: unless-stopped
    ports:
      - "8080:8080"
    environment:
      - OLLAMA_HOST=http://ollama:11434
      - GPU_TYPE=${GPU_TYPE}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    depends_on:
      - ollama

volumes:
  ollama_data:
EOF

    # Start
    docker-compose up -d
    
    success "Full stack deployed!"
    echo ""
    echo "Ollama API: http://$(curl -s ifconfig.me 2>/dev/null || echo 'localhost'):11434"
    echo "Manager UI: http://$(curl -s ifconfig.me 2>/dev/null || echo 'localhost'):8080"
}

# Pull default model
pull_model() {
    log "Pulling default model..."
    sleep 10
    
    if [ "$GPU_TYPE" = "nvidia" ]; then
        docker exec ollama ollama pull llama2 2>/dev/null || true
    else
        docker exec ollama ollama pull tinyllama 2>/dev/null || true
    fi
    
    success "Default model pulled"
}

# Main
main() {
    echo "========================================"
    echo "  Ollama Model Manager Installer"
    echo "  Mode: $DEPLOY_MODE"
    echo "========================================"
    echo ""
    
    # Check root
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root or with sudo"
        exit 1
    fi
    
    detect_gpu
    install_docker
    install_nvidia_docker
    
    # Deploy based on mode
    case $DEPLOY_MODE in
        ollama-only)
            mkdir -p /opt/ollama
            deploy_ollama_only
            ;;
        full|*)
            mkdir -p /opt/ollama-manager
            deploy_full
            ;;
    esac
    
    # Pull model in background
    (sleep 15 && pull_model) &
    
    echo ""
    echo "========================================"
    success "Installation Complete!"
    echo "========================================"
    echo ""
    
    if [ "$DEPLOY_MODE" = "ollama-only" ]; then
        echo "Mode: Ollama Only"
        echo "API: http://localhost:11434"
        echo ""
        echo "To add manager later:"
        echo "  curl -fsSL ... | bash -s full"
    else
        echo "Mode: Full Stack"
        echo "API: http://localhost:11434"
        echo "UI:  http://localhost:8080"
    fi
    
    echo ""
    echo "Commands:"
    echo "  docker-compose -f /opt/ollama/docker-compose.yml logs -f"
    echo "========================================"
}

main "$@"
