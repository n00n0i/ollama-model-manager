# Ollama Model Manager - Production Ready

Enterprise-grade Ollama model management platform with comprehensive UI for model operations, parameter tuning, and monitoring.

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              CLIENT LAYER                                    │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                     React Frontend (TypeScript)                      │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌──────────┐   │    │
│  │  │   Model     │  │   Model     │  │   Parameter │  │  Chat    │   │    │
│  │  │   Browser   │  │   Upload    │  │   Tuning    │  │  Interface│   │    │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └──────────┘   │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         FASTAPI BACKEND (Python)                             │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                         REST API Layer                               │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌──────────┐   │    │
│  │  │  /models    │  │  /parameters│  │   /chat     │  │  /system │   │    │
│  │  │  (CRUD)     │  │  (Tuning)   │  │  (Generate) │  │  (Status)│   │    │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └──────────┘   │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                    │                                         │
└────────────────────────────────────┼──────────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         OLLAMA SERVICE                                       │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    Ollama Server                                     │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │    │
│  │  │   Model     │  │   Model     │  │   LLM       │                 │    │
│  │  │   Registry  │  │   Runtime   │  │   Inference │                 │    │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                 │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 🚀 Quick Start

### Production Install

```bash
curl -fsSL https://raw.githubusercontent.com/n00n0i/ollama-model-manager/main/install-production.sh | sudo bash
```

## Features

- Model Management (Pull, Push, Delete, List)
- Parameter Tuning (Temperature, Top_P, Context Window)
- Model Upload (Custom GGUF files)
- Chat Interface with streaming
- GPU/Resource Monitoring
- System Prompts Management
- API Key Management
- Audit Logging
