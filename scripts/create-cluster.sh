#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/runtime.sh
source "${SCRIPT_DIR}/lib/runtime.sh"

CLUSTER_NAME=poc-devops
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  echo "[OK] Cluster kind '$CLUSTER_NAME' ja existe."
else
  echo "[INFO] Criando cluster kind '$CLUSTER_NAME'..."
  kind create cluster --config kubernetes/kind-config.yaml
fi

prepare_runtime_dir
kind get kubeconfig --name "$CLUSTER_NAME" > "$POC_KUBECONFIG_PATH"
chmod 600 "$POC_KUBECONFIG_PATH"

kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null
kubectl cluster-info --context "kind-${CLUSTER_NAME}"
kubectl wait --for=condition=Ready node --all --timeout=180s

# Promtail cria um watcher por diretorio de logs. O limite padrao pode ser
# insuficiente quando todos os componentes da POC estao ativos.
while IFS= read -r node; do
  docker exec "$node" sysctl -w fs.inotify.max_user_instances=512 >/dev/null
done < <(kind get nodes --name "$CLUSTER_NAME")
