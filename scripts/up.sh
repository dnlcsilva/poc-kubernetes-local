#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

prompt_secret() {
  local variable=$1
  local prompt=$2
  local value=${!variable:-}

  if [[ -z "$value" ]]; then
    if [[ ! -t 0 ]]; then
      echo "[ERRO] ${variable} nao foi definida e o terminal nao e interativo." >&2
      exit 1
    fi
    read -rsp "$prompt" value
    echo
  fi

  if [[ -z "$value" ]]; then
    echo "[ERRO] A senha nao pode ser vazia." >&2
    exit 1
  fi

  printf -v "$variable" '%s' "$value"
  export "$variable"
}

prompt_secret HARBOR_PASSWORD 'Senha do Harbor: '
prompt_secret JENKINS_ADMIN_PASSWORD 'Senha do Jenkins: '

"${SCRIPT_DIR}/check-prereqs.sh"
"${SCRIPT_DIR}/configure-hosts.sh"
"${SCRIPT_DIR}/create-cluster.sh"
"${SCRIPT_DIR}/install-platform.sh"
"${SCRIPT_DIR}/install-harbor.sh"
"${SCRIPT_DIR}/start-ci.sh"
if kubectl get application poc-app -n argocd >/dev/null 2>&1; then
  echo '[INFO] Modo GitOps ja esta ativo; deploy local ignorado.'
else
  "${SCRIPT_DIR}/deploy-app.sh" "${TAG:-1.0.0}"
fi

echo
echo '[OK] POC obrigatoria pronta.'
echo '[INFO] Execute make info para consultar URLs e credenciais.'
echo '[INFO] Para adicionar o diferencial GitOps: make argocd'
