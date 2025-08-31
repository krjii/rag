#!/usr/bin/env bash
# rag/scripts/rag.sh — bring-up/tear-down NVIDIA RAG Blueprint via Docker Compose
set -euo pipefail

# --- CONFIG (override via env) ---
: "${NGC_API_KEY:=}"                         # export NGC_API_KEY=nvapi-...
: "${MODEL_DIRECTORY:=$HOME/.cache/model-cache}"
# Wait timeout for NIM health (first LLM boot can be long on first run)
: "${RAG_HEALTH_TIMEOUT_SEC:=1800}"          # 30 min default
: "${RAG_HEALTH_POLL_SEC:=10}"

# Compose files (relative to repo root)
NIMS_FILE="deploy/compose/nims.yaml"
VDB_FILE="deploy/compose/vectordb.yaml"
INGEST_FILE="deploy/compose/docker-compose-ingestor-server.yaml"
RAG_FILE="deploy/compose/docker-compose-rag-server.yaml"

# Core NIMs we require to be (healthy) before proceeding
REQUIRED_HEALTHY=(
  "nemoretriever-ranking-ms"
  "nemoretriever-embedding-ms"
  "nim-llm-ms"
)

# --- PATHS ---
# Resolve project root as parent of scripts/
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

docker_compose() { sudo docker compose "$@"; }

login_ngc() {
  [[ -n "${NGC_API_KEY}" ]] || { echo "[ERROR] NGC_API_KEY not set"; exit 1; }
  echo "${NGC_API_KEY}" | sudo docker login nvcr.io -u '$oauthtoken' --password-stdin >/dev/null
  echo "[OK] Logged into nvcr.io"
}

ensure_model_cache() {
  mkdir -p "${MODEL_DIRECTORY}"
  export MODEL_DIRECTORY
  echo "[OK] MODEL_DIRECTORY=${MODEL_DIRECTORY}"
}

wait_for_healthy() {
  local deadline=$(( $(date +%s) + RAG_HEALTH_TIMEOUT_SEC ))
  echo "[INFO] Waiting for NIM health: ${REQUIRED_HEALTHY[*]}"
  while :; do
    local all_ok=1
    for name in "${REQUIRED_HEALTHY[@]}"; do
      # Grab status line for this container (if present)
      local line
      line="$(docker ps --format '{{.Names}} {{.Status}}' | awk -v N="$name" '$1==N{print $0}')"
      if [[ -z "$line" ]]; then
        all_ok=0
        echo "  - $name: not started yet"
        continue
      fi
      if [[ "$line" != *"(healthy)"* ]]; then
        all_ok=0
        echo "  - $name: $line"
      else
        echo "  - $name: healthy"
      fi
    done

    if [[ $all_ok -eq 1 ]]; then
      echo "[OK] All required NIMs are healthy."
      return 0
    fi

    if (( $(date +%s) >= deadline )); then
      echo "[ERROR] Timeout waiting for NIM health (${RAG_HEALTH_TIMEOUT_SEC}s)."
      echo "Tip: check logs, e.g.: sudo docker logs -f nim-llm-ms"
      return 1
    fi
    sleep "${RAG_HEALTH_POLL_SEC}"
  done
}

health_ping() {
  curl -s 'http://localhost:8081/v1/health?check_dependencies=true' || true
}

# --- ACTIONS ---
up_onprem() {
  ensure_model_cache
  login_ngc

  echo "[INFO] Starting NIMs (on-prem)"
  docker_compose -f "${repo_root}/${NIMS_FILE}" up -d

  echo "[INFO] Starting Vector DB"
  docker_compose -f "${repo_root}/${VDB_FILE}" up -d

  echo "[INFO] Starting Ingestor"
  docker_compose -f "${repo_root}/${INGEST_FILE}" up -d

  echo "[INFO] Starting RAG server + UI"
  docker_compose -f "${repo_root}/${RAG_FILE}" up -d

  # Block until NIMs are healthy (or timeout)
  wait_for_healthy

  echo "[INFO] RAG health endpoint:"
  health_ping | jq . || true
  echo "[DONE] RAG (on-prem) up — open http://localhost:8090"
}

up_hosted() {
  login_ngc

  echo "[INFO] Starting Vector DB"
  docker_compose -f "${repo_root}/${VDB_FILE}" up -d

  echo "[INFO] Starting Ingestor"
  docker_compose -f "${repo_root}/${INGEST_FILE}" up -d

  echo "[INFO] Starting RAG server + UI"
  docker_compose -f "${repo_root}/${RAG_FILE}" up -d

  echo "[INFO] RAG health endpoint:"
  health_ping | jq . || true
  echo "[DONE] RAG (hosted) up — open http://localhost:8090"
}

down_all() {
  docker_compose -f "${repo_root}/${INGEST_FILE}" down || true
  docker_compose -f "${repo_root}/${RAG_FILE}" down || true
  docker_compose -f "${repo_root}/${NIMS_FILE}" down || true
  docker_compose -f "${repo_root}/${VDB_FILE}" down || true
  echo "[DONE] All services stopped"
}

status() {
  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

usage() {
  cat <<USAGE
Usage:
  scripts/rag.sh up onprem     # start RAG with on-prem NIMs (waits for NIM health)
  scripts/rag.sh up hosted     # start RAG with NVIDIA-hosted NIMs
  scripts/rag.sh down          # stop all stacks
  scripts/rag.sh status        # list running containers

Env:
  export NGC_API_KEY=nvapi-...            (required)
  export MODEL_DIRECTORY=~/.cache/model-cache
  export RAG_HEALTH_TIMEOUT_SEC=1800      (optional)
  export RAG_HEALTH_POLL_SEC=10           (optional)
USAGE
}

# --- MAIN ---
cmd="${1:-}"; arg="${2:-}"
case "${cmd}:${arg}" in
  up:onprem)  up_onprem ;;
  up:hosted)  up_hosted ;;
  down:|down:*) down_all ;;
  status:|status:*) status ;;
  *) usage; exit 1 ;;
esac
