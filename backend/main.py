from fastapi import FastAPI, HTTPException, BackgroundTasks, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from typing import List, Optional, Dict, Any
import httpx
import asyncio
import os
from datetime import datetime

app = FastAPI(
    title="Ollama Model Manager",
    description="Management API for Ollama with GPU support",
    version="1.0.0"
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Config
OLLAMA_HOST = os.getenv("OLLAMA_HOST", "http://ollama:11434")
GPU_TYPE = os.getenv("GPU_TYPE", "cpu")
GPU_COUNT = int(os.getenv("GPU_COUNT", "0"))

# Models
class ModelInfo(BaseModel):
    name: str
    size: int
    modified_at: str
    digest: str
    details: Optional[Dict[str, Any]] = None

class PullModelRequest(BaseModel):
    name: str
    insecure: bool = False

class GenerateRequest(BaseModel):
    model: str
    prompt: str
    system: Optional[str] = None
    template: Optional[str] = None
    context: Optional[List[int]] = None
    stream: bool = False
    raw: bool = False
    format: Optional[str] = None
    options: Optional[Dict[str, Any]] = None

class ModelParameters(BaseModel):
    temperature: float = Field(default=0.7, ge=0.0, le=2.0)
    top_p: float = Field(default=0.9, ge=0.0, le=1.0)
    top_k: int = Field(default=40, ge=0, le=100)
    num_ctx: int = Field(default=2048, ge=512, le=32768)
    num_predict: int = Field(default=-1, ge=-1, le=4096)
    repeat_penalty: float = Field(default=1.1, ge=0.0, le=2.0)
    seed: Optional[int] = None
    stop: Optional[List[str]] = None

class SystemInfo(BaseModel):
    gpu_type: str
    gpu_count: int
    ollama_version: str
    models_loaded: int
    memory_available: Optional[int] = None

# Health check
@app.get("/api/health")
async def health():
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(f"{OLLAMA_HOST}/api/tags", timeout=5.0)
            return {
                "status": "healthy",
                "ollama_connected": response.status_code == 200,
                "gpu_type": GPU_TYPE,
                "gpu_count": GPU_COUNT
            }
    except Exception as e:
        return {
            "status": "unhealthy",
            "error": str(e),
            "gpu_type": GPU_TYPE
        }

# List models
@app.get("/api/models", response_model=List[ModelInfo])
async def list_models():
    async with httpx.AsyncClient() as client:
        try:
            response = await client.get(f"{OLLAMA_HOST}/api/tags")
            if response.status_code != 200:
                raise HTTPException(status_code=500, detail="Failed to fetch models")
            return response.json().get("models", [])
        except httpx.ConnectError:
            raise HTTPException(status_code=503, detail="Ollama service not available")

# Pull model
@app.post("/api/models/pull")
async def pull_model(request: PullModelRequest, background_tasks: BackgroundTasks):
    async def do_pull():
        async with httpx.AsyncClient(timeout=None) as client:
            async with client.stream(
                "POST",
                f"{OLLAMA_HOST}/api/pull",
                json={"name": request.name, "insecure": request.insecure}
            ) as response:
                async for line in response.aiter_lines():
                    print(line)  # Log progress
    
    background_tasks.add_task(do_pull)
    return {"status": "pulling", "model": request.name}

# Delete model
@app.delete("/api/models/{model_name}")
async def delete_model(model_name: str):
    async with httpx.AsyncClient() as client:
        response = await client.delete(
            f"{OLLAMA_HOST}/api/delete",
            json={"name": model_name}
        )
        if response.status_code != 200:
            raise HTTPException(status_code=500, detail="Failed to delete model")
        return {"status": "deleted", "model": model_name}

# Generate completion
@app.post("/api/generate")
async def generate(request: GenerateRequest):
    async with httpx.AsyncClient(timeout=120.0) as client:
        try:
            response = await client.post(
                f"{OLLAMA_HOST}/api/generate",
                json=request.dict(exclude_none=True)
            )
            return response.json()
        except httpx.ReadTimeout:
            raise HTTPException(status_code=504, detail="Generation timeout")

# Get model info
@app.post("/api/show")
async def show_model(name: str):
    async with httpx.AsyncClient() as client:
        response = await client.post(
            f"{OLLAMA_HOST}/api/show",
            json={"name": name}
        )
        return response.json()

# Copy model
@app.post("/api/copy")
async def copy_model(source: str, destination: str):
    async with httpx.AsyncClient() as client:
        response = await client.post(
            f"{OLLAMA_HOST}/api/copy",
            json={"source": source, "destination": destination}
        )
        return {"status": "copied", "from": source, "to": destination}

# Create model from Modelfile
@app.post("/api/create")
async def create_model(name: str, modelfile: str):
    async with httpx.AsyncClient() as client:
        response = await client.post(
            f"{OLLAMA_HOST}/api/create",
            json={"name": name, "modelfile": modelfile}
        )
        return {"status": "created", "model": name}

# Upload GGUF file
@app.post("/api/upload")
async def upload_model(
    file: UploadFile = File(...),
    name: str = "custom-model",
    quantization: str = "Q4_K_M"
):
    # Save uploaded file
    upload_dir = "/data/uploads"
    os.makedirs(upload_dir, exist_ok=True)
    
    file_path = f"{upload_dir}/{file.filename}"
    with open(file_path, "wb") as f:
        content = await file.read()
        f.write(content)
    
    # Create Modelfile
    modelfile = f"""FROM {file_path}
PARAMETER temperature 0.7
PARAMETER top_p 0.9
SYSTEM You are a helpful AI assistant.
"""
    
    # Create model
    async with httpx.AsyncClient() as client:
        response = await client.post(
            f"{OLLAMA_HOST}/api/create",
            json={"name": name, "modelfile": modelfile}
        )
    
    return {
        "status": "uploaded",
        "model": name,
        "file": file.filename,
        "size": len(content)
    }

# Get system info
@app.get("/api/system", response_model=SystemInfo)
async def system_info():
    models = await list_models()
    
    info = SystemInfo(
        gpu_type=GPU_TYPE,
        gpu_count=GPU_COUNT,
        ollama_version="0.1.0",
        models_loaded=len(models)
    )
    
    # Add GPU-specific info
    if GPU_TYPE == "nvidia":
        try:
            import subprocess
            result = subprocess.run(
                ["nvidia-smi", "--query-gpu=memory.free", "--format=csv,noheader,nounits"],
                capture_output=True,
                text=True
            )
            info.memory_available = int(result.stdout.strip()) * 1024 * 1024  # Convert to bytes
        except:
            pass
    
    return info

# GPU Stats (NVIDIA only)
@app.get("/api/gpu/stats")
async def gpu_stats():
    if GPU_TYPE != "nvidia":
        return {"error": "GPU stats only available for NVIDIA"}
    
    try:
        import subprocess
        result = subprocess.run(
            ["nvidia-smi", "--query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu", "--format=csv,noheader"],
            capture_output=True,
            text=True
        )
        
        lines = result.stdout.strip().split('\n')
        gpus = []
        for i, line in enumerate(lines):
            util, mem_used, mem_total, temp = line.split(', ')
            gpus.append({
                "index": i,
                "utilization": util,
                "memory_used": mem_used,
                "memory_total": mem_total,
                "temperature": temp
            })
        
        return {"gpus": gpus}
    except Exception as e:
        return {"error": str(e)}

# Embeddings
@app.post("/api/embeddings")
async def embeddings(model: str, prompt: str):
    async with httpx.AsyncClient() as client:
        response = await client.post(
            f"{OLLAMA_HOST}/api/embeddings",
            json={"model": model, "prompt": prompt}
        )
        return response.json()

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
