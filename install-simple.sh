#!/bin/bash
# Ollama Manager - Direct run (no systemd)

set -e

OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"
INSTALL_DIR="/opt/ollama-manager"

echo "========================================"
echo "  Ollama Model Manager"
echo "========================================"

# Check Ollama
echo "[INFO] Checking Ollama..."
if ! curl -s "$OLLAMA_HOST/api/tags" > /dev/null 2>&1; then
    echo "[ERROR] Ollama not found at $OLLAMA_HOST"
    exit 1
fi
echo "[OK] Ollama is running"

# Create app
echo "[INFO] Creating app..."
mkdir -p "$INSTALL_DIR"

cat > "$INSTALL_DIR/app.py" << 'PYEOF'
import os, httpx
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse

OLLAMA_HOST = os.getenv("OLLAMA_HOST", "http://localhost:11434")
app = FastAPI()
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"])

HTML = '''<!DOCTYPE html>
<html><head><title>Ollama Manager</title>
<style>
body{font-family:sans-serif;background:#0f0f23;color:#fff;padding:2rem}
.card{background:#1a1a2e;padding:1.5rem;border-radius:12px;margin-bottom:1rem}
.btn{background:#667eea;color:white;border:none;padding:0.5rem 1rem;border-radius:6px;cursor:pointer}
input{background:#16162a;border:1px solid #2d2d44;color:white;padding:0.5rem;width:300px}
</style></head>
<body><h1>Ollama Model Manager</h1>
<div class="card"><h3>Pull Model</h3>
<input id="model" placeholder="Model name (e.g., llama2)">
<button class="btn" onclick="pull()">Pull</button></div>
<div class="card"><h3>Installed Models</h3><div id="models">Loading...</div></div>
<script>
async function load(){const r=await fetch("/api/models");const d=await r.json();document.getElementById("models").innerHTML=d.models.map(m=>`<div>${m.name} <button class="btn" onclick="del('${m.name}')">Delete</button></div>`).join("");}
async function pull(){const m=document.getElementById("model").value;await fetch("/api/pull?model="+m,{method:"POST"});alert("Pulling "+m);}
async function del(n){await fetch("/api/delete?model="+n,{method:"DELETE"});load();}
load();
</script></body></html>'''

@app.get("/", response_class=HTMLResponse)
async def root(): return HTML

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
    uvicorn.run(app, host="0.0.0.0", port=8080)
PYEOF

# Install deps
echo "[INFO] Installing dependencies..."
pip3 install fastapi uvicorn httpx --quiet

# Start
echo "[INFO] Starting Manager..."
cd "$INSTALL_DIR"
nohup python3 app.py > manager.log 2>&1 &
echo $! > /tmp/ollama-manager.pid

sleep 2

echo ""
echo "========================================"
echo "✅ Manager UI is running!"
echo "========================================"
echo ""
echo "URL: http://$(hostname -I | awk '{print $1}'):8080"
echo "Log: tail -f $INSTALL_DIR/manager.log"
echo "Stop: kill \$(cat /tmp/ollama-manager.pid)"
echo "========================================"
