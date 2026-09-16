#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/runtime.sh
source "${SCRIPT_DIR}/lib/runtime.sh"

status() {
  printf '\n=== Docker / CI ===\n'
  JENKINS_ADMIN_PASSWORD=unused \
  SONAR_TOKEN=unused \
  HARBOR_PASSWORD=unused \
  POC_KUBECONFIG_PATH="$POC_KUBECONFIG_PATH" \
    docker compose ps 2>/dev/null || true
  printf '\n=== Nodes ===\n'
  kubectl get nodes -o wide 2>/dev/null || true
  printf '\n=== Pods ===\n'
  kubectl get pods -A 2>/dev/null || true
  printf '\n=== Ingress ===\n'
  kubectl get ingress -A 2>/dev/null || true
  printf '\n=== HPA ===\n'
  kubectl get hpa -A 2>/dev/null || true
  printf '\n=== Helm releases ===\n'
  helm list -A 2>/dev/null || true
  printf '\n=== Health ===\n'
  if curl -fsS -H 'Host: poc.local' http://127.0.0.1/healthz 2>/dev/null; then
    echo
    echo '[OK] Aplicacao saudavel.'
  else
    echo '[AVISO] Aplicacao nao respondeu em /healthz.'
  fi

  for endpoint in grafana.local prometheus.local; do
    if curl -fsS -H "Host: ${endpoint}" http://127.0.0.1/ >/dev/null 2>&1; then
      echo "[OK] ${endpoint} acessivel."
    else
      echo "[AVISO] ${endpoint} nao respondeu."
    fi
  done

  if kubectl get ingress argocd-server -n argocd >/dev/null 2>&1; then
    if curl -fsS -H 'Host: argocd.local' http://127.0.0.1/ >/dev/null 2>&1; then
      echo '[OK] argocd.local acessivel.'
    else
      echo '[AVISO] argocd.local nao respondeu.'
    fi
    if kubectl get application poc-app -n argocd >/dev/null 2>&1; then
      sync_status=$(kubectl get application poc-app -n argocd \
        -o jsonpath='{.status.sync.status}' 2>/dev/null || true)
      health_status=$(kubectl get application poc-app -n argocd \
        -o jsonpath='{.status.health.status}' 2>/dev/null || true)
      echo "[INFO] CD pelo Argo: ${sync_status:-Unknown} / ${health_status:-Unknown}."
    else
      echo '[INFO] Argo CD instalado, mas sem Application; deploy permanece no Jenkins.'
    fi
  else
    echo '[INFO] Argo CD opcional nao instalado.'
  fi
}

rollback() {
  local revision=${1:-}

  if kubectl get application poc-app -n argocd >/dev/null 2>&1; then
    echo '[ERRO] Modo GitOps ativo. Faca o rollback no estado desejado do Argo CD.' >&2
    exit 1
  fi

  if ! helm status poc-app -n poc >/dev/null 2>&1; then
    echo '[ERRO] Release poc-app nao encontrada no namespace poc.'
    exit 1
  fi

  if [[ -z "$revision" ]]; then
    current=$(helm history poc-app -n poc -o json | python3 -c \
      'import json,sys; h=json.load(sys.stdin); print(max(int(x["revision"]) for x in h))')
    if (( current <= 1 )); then
      echo '[ERRO] Nao existe revisao anterior para rollback.'
      exit 1
    fi
    revision=$((current - 1))
  fi

  echo "[INFO] Rollback para revisao ${revision}..."
  helm rollback poc-app "$revision" -n poc --wait --timeout 5m
  kubectl rollout status deployment/poc-app -n poc --timeout=180s
}

case "${1:-status}" in
  status) status ;;
  logs) kubectl logs -n poc deployment/poc-app --all-containers=true --tail=100 -f ;;
  rollback) rollback "${2:-}" ;;
  *) echo "[ERRO] Operacao desconhecida: $1" >&2; exit 2 ;;
esac
