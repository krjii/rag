# NVIDIA RAG Blueprint — Project Setup & Scripts

This project includes helper scripts under `scripts/` to simplify deployment of the NVIDIA RAG Blueprint with Docker Compose.

---

## 🚀 Quickstart

1. Set your NGC API key:
   export NGC_API_KEY="nvapi-..."

2. Bring up the stack (on-prem GPU mode):
   ./scripts/rag.sh up onprem

3. Open the playground:
   <http://localhost:8090>

For hosted NIMs (no GPU required):
   export NGC_API_KEY="nvapi-..."
   ./scripts/rag.sh up hosted

---

## 📦 Prerequisites

1. NGC API Key  
   - Generate an API key from <https://org.ngc.nvidia.com/setup/api-keys>  
   - Export it in your shell:  
     export NGC_API_KEY="nvapi-..."

2. Docker & Compose  
   - Install Docker Engine and Docker Compose plugin (v2.29.1+)  
   - Authenticate Docker to nvcr.io:  
     echo "${NGC_API_KEY}" | sudo docker login nvcr.io -u '$oauthtoken' --password-stdin

3. NVIDIA GPU Support (for on-prem models)  
   - NVIDIA drivers + NVIDIA Container Toolkit installed  
   - Test with:  
     nvidia-smi  
     sudo docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi

---

## 🛠 Scripts

All helper commands live in scripts/rag.sh.

### Start RAG (On-Prem NIMs)

Runs ingestion, Milvus vector DB, RAG server + Playground, and all required NIMs locally. Waits until core NIMs are (healthy) before returning.

   export NGC_API_KEY="nvapi-..."
   ./scripts/rag.sh up onprem

⚠️ First boot of nim-llm-ms may take up to 30 minutes (model download + engine build). Subsequent boots are faster thanks to cached models in ~/.cache/model-cache.

### Start RAG (Hosted NIMs)

If you don’t have a suitable GPU, use NVIDIA-hosted NIMs instead:

   export NGC_API_KEY="nvapi-..."
   ./scripts/rag.sh up hosted

### Check Status

   ./scripts/rag.sh status

Shows container name, status, and ports.

### Stop All Services

   ./scripts/rag.sh down

Stops RAG server, ingestor, Milvus, and NIMs.

---

## ⚙️ Configuration

- Model Cache Directory  
  Default: ~/.cache/model-cache  
  Override with:  
    export MODEL_DIRECTORY=/path/to/cache

- Health Wait Timeout  
  Default: 1800s (30 min)  
  Change with:  
    export RAG_HEALTH_TIMEOUT_SEC=3600

- Milvus GPU Index/Search  
  For A100 / B200 GPUs, NVIDIA recommends CPU indexing:  
    export APP_VECTORSTORE_ENABLEGPUSEARCH=False  
    export APP_VECTORSTORE_ENABLEGPUINDEX=False

- GPU Assignments (On-Prem NIMs)  
  Example for embedding/ranking services:  
    export EMBEDDING_MS_GPU_ID=0  
    export RANKING_MS_GPU_ID=0  
  Example for LLM (on A100, 2 GPUs recommended):  
    export LLM_MS_GPU_ID=1,2

---

## 🌐 Playground Access

Once running, open:  
👉 <http://localhost:8090>  

Use the upload tab to ingest files or follow notebooks for programmatic API usage.

---

## 🗺 Architecture Overview

flowchart LR
    A[Data Files / PDFs] --> B[Ingestor Server]
    B --> C[Vector DB (Milvus + MinIO + etcd)]
    B --> D[NIMs (Embedding, Ranking, OCR)]
    D --> C
    C --> E[RAG Server]
    D --> E
    E --> F[Playground UI (http://localhost:8090)]
    E --> G[Client Apps / API Calls]

- Ingestor Server — handles data ingestion and preprocessing  
- Vector DB — Milvus stores embeddings + metadata  
- NIMs — NVIDIA microservices for embedding, ranking, OCR, and LLM  
- RAG Server — query orchestration  
- Playground UI — simple web frontend to test queries  

---

## 🐛 Troubleshooting

- LLM container takes too long:  
  sudo docker logs -f nim-llm-ms

- GPU not detected in container:  
  Verify nvidia-smi works both on host and in a CUDA test container

- Config changes not applying in frontend:  
  sudo docker compose -f deploy/compose/docker-compose-rag-server.yaml up -d --build

---
