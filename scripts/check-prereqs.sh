#!/usr/bin/env bash
set -euo pipefail

required=(docker kind kubectl helm curl git python3)
missing=0
for cmd in "${required[@]}"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[ERRO] Comando ausente: $cmd"
    missing=1
  fi
done

if ! docker compose version >/dev/null 2>&1; then
  echo "[ERRO] Docker Compose v2 (docker compose) nao esta disponivel."
  missing=1
fi

if (( missing )); then
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "[ERRO] Docker daemon nao esta acessivel para o usuario atual."
  exit 1
fi

require_minimum_version() {
  local tool=$1 current=$2 minimum=$3

  if [[ -z "$current" ]] ||
     [[ $(printf '%s\n' "$minimum" "$current" | sort -V | head -n 1) != "$minimum" ]]; then
    echo "[ERRO] ${tool} ${minimum} ou superior e necessario; encontrado: ${current:-desconhecido}."
    return 1
  fi
}

kind_version=$(kind version 2>/dev/null | awk '{print $2}' | sed 's/^v//')
kubectl_version=$(kubectl version --client -o json 2>/dev/null |
  python3 -c 'import json, sys; print(json.load(sys.stdin)["clientVersion"]["gitVersion"].lstrip("v"))' 2>/dev/null || true)
helm_version=$(helm version --short 2>/dev/null | sed -E 's/^v//; s/\+.*$//')
docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null)
compose_version=$(docker compose version --short 2>/dev/null | sed 's/^v//')
python_version=$(python3 -c 'import platform; print(platform.python_version())')

require_minimum_version kind "$kind_version" 0.33.0
require_minimum_version kubectl "$kubectl_version" 1.37.0
require_minimum_version Helm "$helm_version" 3.22.0
if [[ ${helm_version%%.*} != 3 ]]; then
  echo "[ERRO] Esta POC foi validada com Helm 3.x; encontrado: ${helm_version}. Helm 4 ainda nao foi homologado."
  exit 1
fi
require_minimum_version 'Docker Engine' "$docker_version" 20.10.0
require_minimum_version 'Docker Compose' "$compose_version" 2.0.0
require_minimum_version Python "$python_version" 3.12.0

mem_bytes=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)
cpus=$(docker info --format '{{.NCPU}}' 2>/dev/null || echo 0)
if [[ "$mem_bytes" =~ ^[0-9]+$ ]] && (( mem_bytes > 0 )); then
  mem_gb=$(( mem_bytes / 1024 / 1024 / 1024 ))
  if (( mem_gb < 12 )); then
    echo "[AVISO] Docker reporta ${mem_gb} GB de RAM. Para a stack completa, 16 GB ou mais e recomendado."
  fi
fi
if [[ "$cpus" =~ ^[0-9]+$ ]] && (( cpus > 0 && cpus < 4 )); then
  echo "[AVISO] Docker reporta ${cpus} CPU(s). 4 ou mais e recomendado."
fi

echo "[OK] Pre-requisitos validados."
echo "[INFO] kind=${kind_version} kubectl=${kubectl_version} helm=${helm_version} docker=${docker_version} compose=${compose_version} python=${python_version}"
