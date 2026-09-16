#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/runtime.sh
source "${SCRIPT_DIR}/lib/runtime.sh"

remove_project_images() {
  local image

  while IFS= read -r image; do
    [[ "$image" == poc-app:* ]] || continue
    echo "[INFO] Removendo imagem ${image}..."
    docker image rm "$image" >/dev/null 2>&1 || \
      echo "[AVISO] Nao foi possivel remover ${image}."
  done < <(docker image ls --filter 'reference=poc-app:*' \
    --format '{{.Repository}}:{{.Tag}}' 2>/dev/null)

  image=poc-devops-jenkins:latest
  if docker image inspect "$image" >/dev/null 2>&1; then
    echo "[INFO] Removendo imagem ${image}..."
    docker image rm "$image" >/dev/null 2>&1 || \
      echo "[AVISO] Nao foi possivel remover ${image}."
  fi
}

JENKINS_ADMIN_PASSWORD=unused \
SONAR_TOKEN=unused \
HARBOR_PASSWORD=unused \
POC_KUBECONFIG_PATH="$POC_KUBECONFIG_PATH" \
  docker compose down -v --remove-orphans 2>/dev/null || true
kind delete cluster --name poc-devops || true
remove_project_images
rm -rf .venv "$POC_RUNTIME_DIR"

echo '[OK] Ambiente removido.'
