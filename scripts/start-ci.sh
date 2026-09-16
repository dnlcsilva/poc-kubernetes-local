#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/runtime.sh
source "${SCRIPT_DIR}/lib/runtime.sh"

prepare_runtime_dir
HOST_PROJECT_PATH=${HOST_PROJECT_PATH:-$(pwd)}
HARBOR_USER=${HARBOR_USER:-admin}
JENKINS_ADMIN_USER=${JENKINS_ADMIN_USER:-admin}
: "${HARBOR_PASSWORD:?Defina HARBOR_PASSWORD antes de iniciar o CI.}"
: "${JENKINS_ADMIN_PASSWORD:?Defina JENKINS_ADMIN_PASSWORD antes de iniciar o CI.}"

if [[ ! -s "$POC_KUBECONFIG_PATH" ]]; then
  echo "[ERRO] Kubeconfig da POC nao encontrado. Execute 'make up' primeiro."
  exit 1
fi

export HOST_PROJECT_PATH HARBOR_USER HARBOR_PASSWORD
export JENKINS_ADMIN_USER JENKINS_ADMIN_PASSWORD POC_KUBECONFIG_PATH

# Sobe Sonar primeiro para gerar um token automaticamente.
SONAR_TOKEN=bootstrap-pending docker compose up -d sonar-db sonarqube

printf '[INFO] Aguardando SonarQube'
sonar_ready=0
for _ in $(seq 1 90); do
  status=$(curl -fsS http://127.0.0.1:9000/api/system/status 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status", ""))' 2>/dev/null || true)
  if [[ "$status" == "UP" ]]; then
    sonar_ready=1
    echo
    break
  fi
  printf '.'
  sleep 2
done

if (( ! sonar_ready )); then
  echo
echo "[ERRO] SonarQube nao ficou UP."
  docker compose logs --tail=100 sonarqube
  exit 1
fi

SONAR_ADMIN_USER=${SONAR_ADMIN_USER:-admin}
SONAR_ADMIN_PASSWORD=${SONAR_ADMIN_PASSWORD:-admin}
curl -fsS -u "${SONAR_ADMIN_USER}:${SONAR_ADMIN_PASSWORD}" -X POST \
  'http://127.0.0.1:9000/api/user_tokens/revoke' \
  --data-urlencode 'name=poc-jenkins' >/dev/null 2>&1 || true

token_json=$(curl -fsS -u "${SONAR_ADMIN_USER}:${SONAR_ADMIN_PASSWORD}" -X POST \
  'http://127.0.0.1:9000/api/user_tokens/generate' \
  --data-urlencode 'name=poc-jenkins' || true)

SONAR_TOKEN=$(printf '%s' "$token_json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("token", ""))' 2>/dev/null || true)
if [[ -z "$SONAR_TOKEN" ]]; then
  echo "[ERRO] Nao foi possivel gerar o token do SonarQube automaticamente."
  echo "Confirme SONAR_ADMIN_USER e SONAR_ADMIN_PASSWORD e execute novamente."
  exit 1
fi
export SONAR_TOKEN

# --build garante que Jenkinsfile/JCasC do repositorio sejam incorporados.
docker compose up -d --build jenkins

printf '[INFO] Aguardando Jenkins'
for _ in $(seq 1 90); do
  if curl -fsS http://127.0.0.1:8080/login >/dev/null 2>&1; then
    echo
    echo "[OK] Jenkins pronto: http://localhost:8080"
    echo "[OK] Usuario Jenkins: ${JENKINS_ADMIN_USER}"
    echo "[OK] Pipeline local pre-criado: poc-kubernetes-local"
    exit 0
  fi
  printf '.'
  sleep 2
done

echo
echo "[ERRO] Jenkins nao respondeu no tempo esperado."
docker compose logs --tail=100 jenkins
exit 1
