#!/bin/bash
#
# Standalone Ollama Model Manager (No Docker)
# Runs directly on host with Python
#

set -e

OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"
MANAGER_PORT="${MANAGER_PORT:-8080}"
INSTALL_DIR="${INSTALL_DIR:-/opt/ollama-manager}"

echo "========================================"
echo "  Ollama Model Manager (Standalone)"
echo "========================================"
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check Ollama
check_ollama() {
    log "Checking Ollama at $OLLAMA_HOST..."
    if curl -s "$OLLAMA_HOST/api/tags" > /dev/null 2>&1; then
        success "Ollama is running!"
    else
        error "Ollama not found at $OLLAMA_HOST"
        exit 1
    fi
}

# Install Python
install_python() {
    if ! command -v python3 &> /dev/null; then
        log "Installing Python..."
        apt-get update
        apt-get install -y python3 python3-pip
    fi
    success "Python ready"
}

# Create app
create_app() {
    log "Creating Manager app..."
    mkdir -p "$INSTALL_DIR"
    
    cat > "$INSTALL_DIR/app.py" << 'PYEOF'
import os
import httpx
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse

OLLAMA_HOST = os.getenv("OLLAMA_HOST", "http://localhost:11434")
app = FastAPI()

app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"])

HTML = '''
<!DOCTYPE html>
<html>
<head>
    <title>Ollama Manager</title>
    <style>
        body { font-family: sans-serif; background: #0f0f23; color: #fff; padding: 2rem; }
        .card { background: #1a1a2e; padding: 1.5rem; border-radius: 12px; margin-bottom: 1rem; }
        .btn { background: #667eea; color: white; border: none; padding: 0.5rem 1rem; border-radius: 6px; cursor: pointer; }
        input { background: #16162a; border: 1px solid #2d2d44; color: white; padding: 0.5rem; border-radius: 6px; width: 300px; }
    </style>
</head>
<body>
    <h1>Ollama Model Manager</h1>
    <div class="card">
        <h3>Pull Model</h3>
        <input id="model" placeholder="Model name (e.g., llama2)">
        <button class="btn" onclick="pull()">Pull</button>
    </div>
    <div class="card">
        <h3>Installed Models</h3>
        <div id="models">Loading...</div>
    </div>
    <script>
        async function loadModels() {
            const res = await fetch("/api/models");
            const data = await res.json();
            document.getElementById("models").innerHTML = data.models.map(m => 
                `<div>${m.name} <button class="btn" onclick="del('${m.name}')">Delete</button></div>`
            ).join("");
        }
        async function pull() {
            const model = document.getElementById("model").value;
            await fetch("/api/pull?model=" + model, {method: "POST"});
            alert("Pulling " + model);
        }
        async function del(name) {
            await fetch("/api/delete?model=" + name, {method: "DELETE"});
            loadModels();
        }
        loadModels();
    </script>
</body>
</html>
'''

@app.get("/", response_class=HTMLResponse)
async def root():
    return HTML

@app.get("/api/models")
async def list_models():
    async with httpx.AsyncClient() as client:
        r = await client.get(f"{OLLAMA_HOST}/api/tags")
        return r.json()

@app.post("/api/pull")
async def pull(model: str):
    async with httpx.AsyncClient(timeout=None) as client:
        await client.post(f"{OLLAMA_HOST}/api/pull", json={"name": model})
    return {"status": "pulling"}

@app.delete("/api/delete")
async def delete(model: str):
    async with httpx.AsyncClient() as client:
        await client.delete(f"{OLLAMA_HOST}/api/delete", json={"name": model})
    return {"status": "deleted"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("MANAGER_PORT", "8080")))
PYEOF

    success "App created"
}

# Install deps
install_deps() {
    log "Installing Python dependencies..."
    pip3 install fastapi uvicorn httpx --break-system-packages 2>/dev/null || pip3 install fastapi uvicorn httpx
    success "Dependencies installed"
}

# Create systemd service
create_service() {
    log "Creating systemd service..."
    
    cat > /etc/systemd/system/ollama-manager.service << EOF
[Unit]
Description=Ollama Model Manager
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
Environment="OLLAMA_HOST=$OLLAMA_HOST"
Environment="MANAGER_PORT=$MANAGER_PORT"
ExecStart=/usr/bin/python3 $INSTALL_DIR/app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ollama-manager
    systemctl start ollama-manager
    
    success "Service created and started"
}

# Main
main() {
    check_ollama
    install_python
    create_app
    install_deps
    create_service
    
    echo ""
    echo "========================================"
    success "Manager UI is running!"
    echo "========================================"
    echo ""
    echo "URL: http://$(hostname -I | awk '{print $1}'):$MANAGER_PORT"
    echo ""
    echo "Commands:"
    echo "  systemctl status ollama-manager"
    echo "  systemctl restart ollama-manager"
    echo "========================================"
}

main "$@"
