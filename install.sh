#!/bin/bash
#
# Ollama + Model Manager - Unified Production Installer
# Auto-detects GPU and deploys accordingly
#

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Configuration
readonly INSTALL_DIR="${INSTALL_DIR:-/opt/ollama-manager}"
readonly OLLAMA_PORT="${OLLAMA_PORT:-11434}"
readonly UI_PORT="${UI_PORT:-8080}"
readonly DATA_DIR="${DATA_DIR:-/var/lib/ollama}"

# Logging
log_info() { echo -e "${BLUE}[INFO]${NC} $(date '+%H:%M:%S') - $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $(date '+%H:%M:%S') - $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $(date '+%H:%M:%S') - $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') - $1"; }

# Detect GPU
detect_gpu() {
    log_info "Detecting GPU..."
    
    GPU_TYPE="cpu"
    GPU_COUNT=0
    
    # Check NVIDIA
    if command -v nvidia-smi &> /dev/null; then
        GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader 2>/dev/null | head -1 || echo "0")
        if [ "$GPU_COUNT" -gt 0 ]; then
            GPU_TYPE="nvidia"
            GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
            VRAM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null | head -1)
            log_success "NVIDIA GPU detected: $GPU_MODEL ($VRAM)"
        fi
    fi
    
    # Check AMD
    if [ "$GPU_TYPE" = "cpu" ] && command -v rocm-smi &> /dev/null; then
        GPU_COUNT=$(rocm-smi --showcount 2>/dev/null | grep -o '[0-9]\+' | head -1 || echo "0")
        if [ "$GPU_COUNT" -gt 0 ]; then
            GPU_TYPE="amd"
            log_success "AMD GPU detected"
        fi
    fi
    
    # Check Apple Silicon
    if [ "$GPU_TYPE" = "cpu" ] && [[ "$OSTYPE" == "darwin"* ]]; then
        if sysctl -n hw.optional.arm64 2>/dev/null | grep -q "1"; then
            GPU_TYPE="apple"
            log_success "Apple Silicon detected"
        fi
    fi
    
    if [ "$GPU_TYPE" = "cpu" ]; then
        log_warn "No GPU detected - will use CPU mode"
    fi
    
    export GPU_TYPE
    export GPU_COUNT
}

# Install Docker
install_docker() {
    if command -v docker &> /dev/null; then
        log_success "Docker already installed"
        return 0
    fi
    
    log_info "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    log_success "Docker installed"
}

# Install NVIDIA Docker runtime
install_nvidia_docker() {
    if [ "$GPU_TYPE" != "nvidia" ]; then
        return 0
    fi
    
    log_info "Installing NVIDIA Container Toolkit..."
    
    # Add NVIDIA package repositories
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
    curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
    curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | tee /etc/apt/sources.list.d/nvidia-docker.list
    
    apt-get update
    apt-get install -y nvidia-docker2
    systemctl restart docker
    
    log_success "NVIDIA Container Toolkit installed"
}

# Create directories
create_directories() {
    log_info "Creating directories..."
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$DATA_DIR/models"
    mkdir -p "$DATA_DIR/uploads"
    mkdir -p "$DATA_DIR/logs"
    mkdir -p /etc/ollama-manager
    
    log_success "Directories created"
}

# Generate Docker Compose
generate_docker_compose() {
    log_info "Generating Docker Compose configuration..."
    
    # Base Ollama service
    cat > "$INSTALL_DIR/docker-compose.yml" << EOF
version: '3.8'

services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    ports:
      - "${OLLAMA_PORT}:11434"
    volumes:
      - ${DATA_DIR}/models:/root/.ollama
      - ${DATA_DIR}/logs:/var/log/ollama
    environment:
      - OLLAMA_HOST=0.0.0.0
      - OLLAMA_ORIGINS=*
EOF

    # Add GPU configuration based on detection
    if [ "$GPU_TYPE" = "nvidia" ]; then
        cat >> "$INSTALL_DIR/docker-compose.yml" << EOF
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
EOF
        log_success "NVIDIA GPU support configured"
        
    elif [ "$GPU_TYPE" = "amd" ]; then
        cat >> "$INSTALL_DIR/docker-compose.yml" << EOF
    devices:
      - /dev/kfd:/dev/kfd
      - /dev/dri:/dev/dri
    group_add:
      - video
EOF
        log_success "AMD GPU support configured"
        
    elif [ "$GPU_TYPE" = "apple" ]; then
        log_warn "Apple Silicon - using CPU mode in Docker"
    else
        log_info "CPU-only mode configured"
    fi

    # Add Management UI service
    cat >> "$INSTALL_DIR/docker-compose.yml" << EOF

  manager:
    image: n00n0i/ollama-model-manager:latest
    container_name: ollama-manager
    restart: unless-stopped
    ports:
      - "${UI_PORT}:8080"
    environment:
      - OLLAMA_HOST=http://ollama:11434
      - OLLAMA_PORT=${OLLAMA_PORT}
      - DATA_DIR=/data
      - GPU_TYPE=${GPU_TYPE}
      - GPU_COUNT=${GPU_COUNT}
    volumes:
      - ${DATA_DIR}/uploads:/data/uploads
      - ${DATA_DIR}/logs:/data/logs
      - /var/run/docker.sock:/var/run/docker.sock:ro
    depends_on:
      - ollama
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Optional: GPU Monitoring for NVIDIA
EOF

    if [ "$GPU_TYPE" = "nvidia" ]; then
        cat >> "$INSTALL_DIR/docker-compose.yml" << EOF
  gpu-exporter:
    image: nvidia/dcgm-exporter:latest
    container_name: ollama-gpu-exporter
    restart: unless-stopped
    ports:
      - "9400:9400"
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]

  prometheus:
    image: prom/prometheus:latest
    container_name: ollama-prometheus
    restart: unless-stopped
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus

  grafana:
    image: grafana/grafana:latest
    container_name: ollama-grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana_data:/var/lib/grafana

volumes:
  prometheus_data:
  grafana_data:
EOF
    fi

    log_success "Docker Compose configuration generated"
}

# Generate Prometheus config for GPU monitoring
generate_prometheus_config() {
    if [ "$GPU_TYPE" != "nvidia" ]; then
        return 0
    fi
    
    cat > "$INSTALL_DIR/prometheus.yml" << EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'gpu'
    static_configs:
      - targets: ['gpu-exporter:9400']
  - job_name: 'ollama'
    static_configs:
      - targets: ['ollama:11434']
EOF
    
    log_success "Prometheus configuration generated"
}

# Create systemd service
create_systemd_service() {
    log_info "Creating systemd service..."
    
    cat > /etc/systemd/system/ollama-manager.service << EOF
[Unit]
Description=Ollama + Model Manager
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${INSTALL_DIR}
Environment="GPU_TYPE=${GPU_TYPE}"
Environment="COMPOSE_PROJECT_NAME=ollama-manager"
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
ExecReload=/usr/local/bin/docker-compose restart
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ollama-manager
    log_success "Systemd service created"
}

# Create management CLI
create_cli() {
    log_info "Creating management CLI..."
    
    cat > /usr/local/bin/ollama-manager << 'EOF'
#!/bin/bash
# Ollama Manager CLI

COMMAND=${1:-status}
INSTALL_DIR="/opt/ollama-manager"

case $COMMAND in
    start)
        systemctl start ollama-manager
        echo "✅ Ollama Manager started"
        ;;
    stop)
        systemctl stop ollama-manager
        echo "⏹️  Ollama Manager stopped"
        ;;
    restart)
        systemctl restart ollama-manager
        echo "🔄 Ollama Manager restarted"
        ;;
    status)
        echo "📊 Ollama Manager Status"
        echo "========================"
        systemctl status ollama-manager --no-pager
        echo ""
        echo "🐳 Docker Containers:"
        docker-compose -f $INSTALL_DIR/docker-compose.yml ps
        ;;
    logs)
        docker-compose -f $INSTALL_DIR/docker-compose.yml logs -f
        ;;
    update)
        echo "🔄 Updating Ollama Manager..."
        cd $INSTALL_DIR
        docker-compose pull
        docker-compose up -d
        echo "✅ Update complete"
        ;;
    gpu)
        echo "🎮 GPU Information:"
        if command -v nvidia-smi &> /dev/null; then
            nvidia-smi
        elif command -v rocm-smi &> /dev/null; then
            rocm-smi
        else
            echo "No GPU detected"
        fi
        ;;
    models)
        echo "📦 Installed Models:"
        curl -s http://localhost:11434/api/tags | jq -r '.models[].name' 2>/dev/null || echo "Ollama not ready"
        ;;
    *)
        echo "Usage: ollama-manager {start|stop|restart|status|logs|update|gpu|models}"
        ;;
esac
EOF

    chmod +x /usr/local/bin/ollama-manager
    log_success "CLI created: ollama-manager"
}

# Pull default models
pull_default_models() {
    log_info "Pulling default models..."
    
    # Wait for Ollama to be ready
    sleep 10
    
    # Pull small models based on GPU
    if [ "$GPU_TYPE" = "cpu" ]; then
        log_info "Pulling CPU-optimized models..."
        docker exec ollama ollama pull tinyllama || true
        docker exec ollama ollama pull phi || true
    else
        log_info "Pulling GPU-optimized models..."
        docker exec ollama ollama pull llama2 || true
        docker exec ollama ollama pull codellama || true
    fi
    
    log_success "Default models pulled"
}

# Main installation
main() {
    echo "================================"
    echo "  Ollama + Model Manager"
    echo "  Unified Installer"
    echo "================================"
    echo
    
    detect_gpu
    install_docker
    
    if [ "$GPU_TYPE" = "nvidia" ]; then
        install_nvidia_docker
    fi
    
    create_directories
    generate_docker_compose
    generate_prometheus_config
    create_systemd_service
    create_cli
    
    # Start services
    log_info "Starting services..."
    cd "$INSTALL_DIR"
    docker-compose up -d
    
    # Pull models in background
    (sleep 15 && pull_default_models) &
    
    echo
    echo "================================"
    log_success "Installation Complete!"
    echo "================================"
    echo
    echo "🎮 GPU Type: ${GPU_TYPE}"
    echo "📊 Management UI: http://localhost:${UI_PORT}"
    echo "🔌 Ollama API: http://localhost:${OLLAMA_PORT}"
    
    if [ "$GPU_TYPE" = "nvidia" ]; then
        echo "📈 GPU Monitoring: http://localhost:3000 (admin/admin)"
        echo "📊 Prometheus: http://localhost:9090"
    fi
    
    echo
    echo "🛠️  Management Commands:"
    echo "   ollama-manager start     - Start services"
    echo "   ollama-manager stop      - Stop services"
    echo "   ollama-manager status    - Check status"
    echo "   ollama-manager logs      - View logs"
    echo "   ollama-manager gpu       - GPU info"
    echo "   ollama-manager models    - List models"
    echo
}

main "$@"
