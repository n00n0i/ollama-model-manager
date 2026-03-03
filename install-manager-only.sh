#!/bin/bash
#
# Deploy only Ollama Model Manager UI
# Assumes Ollama is already running
#

set -e

OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"
MANAGER_PORT="${MANAGER_PORT:-8080}"

echo "========================================"
echo "  Ollama Model Manager UI Only"
echo "========================================"
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }

# Check if Ollama is running
check_ollama() {
    log "Checking Ollama..."
    if curl -s "$OLLAMA_HOST/api/tags" > /dev/null 2>&1; then
        success "Ollama is running at $OLLAMA_HOST"
    else
        echo "❌ Ollama not found at $OLLAMA_HOST"
        echo "Please start Ollama first or set OLLAMA_HOST"
        exit 1
    fi
}

# Install Docker if needed
install_docker() {
    if ! command -v docker &> /dev/null; then
        log "Installing Docker..."
        curl -fsSL https://get.docker.com | sh
        success "Docker installed"
    fi
}

# Deploy Manager Only
deploy_manager() {
    log "Deploying Model Manager UI..."
    
    mkdir -p /opt/ollama-manager
    cd /opt/ollama-manager
    
    # Create simple Python backend
    cat > app.py << 'PYEOF'
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import httpx
import os

app = FastAPI(title="Ollama Model Manager")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

OLLAMA_HOST = os.getenv("OLLAMA_HOST", "http://localhost:11434")

@app.get("/api/health")
async def health():
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(f"{OLLAMA_HOST}/api/tags", timeout=5.0)
            return {"status": "healthy", "ollama_connected": response.status_code == 200}
    except:
        return {"status": "unhealthy", "ollama_connected": False}

@app.get("/api/models")
async def list_models():
    async with httpx.AsyncClient() as client:
        response = await client.get(f"{OLLAMA_HOST}/api/tags")
        return response.json()

@app.post("/api/models/pull")
async def pull_model(name: str):
    async with httpx.AsyncClient(timeout=None) as client:
        response = await client.post(
            f"{OLLAMA_HOST}/api/pull",
            json={"name": name}
        )
        return {"status": "pulling", "model": name}

@app.delete("/api/models/{model_name}")
async def delete_model(model_name: str):
    async with httpx.AsyncClient() as client:
        response = await client.delete(
            f"{OLLAMA_HOST}/api/delete",
            json={"name": model_name}
        )
        return {"status": "deleted"}

@app.post("/api/generate")
async def generate(request: dict):
    async with httpx.AsyncClient(timeout=120.0) as client:
        response = await client.post(
            f"{OLLAMA_HOST}/api/generate",
            json=request
        )
        return response.json()

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
PYEOF

    # Create Dockerfile
    cat > Dockerfile << 'DOCEOF'
FROM python:3.11-slim
WORKDIR /app
RUN pip install fastapi uvicorn httpx
COPY app.py .
EXPOSE 8080
CMD ["python", "app.py"]
DOCEOF

    # Create docker-compose
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  manager:
    build: .
    container_name: ollama-manager
    restart: unless-stopped
    ports:
      - "8080:8080"
    environment:
      - OLLAMA_HOST=${OLLAMA_HOST:-http://host.docker.internal:11434}
    extra_hosts:
      - "host.docker.internal:host-gateway"
EOF

    # Build and run
    docker-compose up -d --build
    
    success "Manager UI deployed!"
}

# Main
main() {
    check_ollama
    install_docker
    deploy_manager
    
    echo ""
    echo "========================================"
    success "Model Manager UI is ready!"
    echo "========================================"
    echo ""
    echo "🌐 Manager UI: http://localhost:8080"
    echo "🔌 Ollama API: $OLLAMA_HOST"
    echo ""
    echo "Commands:"
    echo "  docker-compose -f /opt/ollama-manager/docker-compose.yml logs -f"
    echo "========================================"
}

main "$@"
