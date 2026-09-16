#!/usr/bin/env bash
set -euo pipefail

HARBOR_HOST=harbor.local
: "${HARBOR_PASSWORD:?Defina HARBOR_PASSWORD antes de instalar o Harbor.}"
HARBOR_CHART_VERSION=1.19.2

helm repo add harbor https://helm.goharbor.io --force-update >/dev/null
helm repo update >/dev/null

helm upgrade --install harbor harbor/harbor \
  --version "$HARBOR_CHART_VERSION" \
  -n harbor --create-namespace \
  --set expose.type=ingress \
  --set expose.tls.enabled=false \
  --set expose.ingress.className=nginx \
  --set expose.ingress.hosts.core="$HARBOR_HOST" \
  --set externalURL="http://${HARBOR_HOST}" \
  --set harborAdminPassword="$HARBOR_PASSWORD" \
  --set trivy.enabled=false \
  --wait --timeout 15m

printf '[INFO] Aguardando API do Harbor'
harbor_ready=0
for _ in $(seq 1 60); do
  if curl -fsS --resolve "${HARBOR_HOST}:80:127.0.0.1" "http://${HARBOR_HOST}/api/v2.0/health" >/dev/null 2>&1; then
    harbor_ready=1
    echo
    break
  fi
  printf '.'
  sleep 2
done

if (( ! harbor_ready )); then
  echo
  echo "[ERRO] A API do Harbor nao respondeu dentro do tempo esperado."
  kubectl get pods -n harbor -o wide || true
  kubectl get ingress -n harbor || true
  exit 1
fi

# Projeto publico para os nodes kind conseguirem realizar pull sem imagePullSecret.
response_file=$(mktemp /tmp/poc-harbor-project.XXXXXX)
trap 'rm -f "$response_file"' EXIT
http_code=$(curl -sS -o "$response_file" -w '%{http_code}' \
  --resolve "${HARBOR_HOST}:80:127.0.0.1" \
  -u "admin:${HARBOR_PASSWORD}" \
  -H 'Content-Type: application/json' \
  -X POST "http://${HARBOR_HOST}/api/v2.0/projects" \
  -d '{"project_name":"poc","public":true}' || true)

case "$http_code" in
  201) echo "[OK] Projeto Harbor 'poc' criado." ;;
  409)
    project_json=$(curl -fsS \
      --resolve "${HARBOR_HOST}:80:127.0.0.1" \
      -u "admin:${HARBOR_PASSWORD}" \
      "http://${HARBOR_HOST}/api/v2.0/projects/poc")
    if ! PROJECT_JSON="$project_json" python3 -c \
      'import json, os, sys; data=json.loads(os.environ["PROJECT_JSON"]); sys.exit(0 if str(data.get("metadata", {}).get("public", "")).lower() == "true" else 1)'; then
      echo "[ERRO] O projeto Harbor 'poc' ja existe, mas nao esta publico."
      exit 1
    fi
    echo "[OK] Projeto Harbor 'poc' ja existe e esta publico."
    ;;
  *)
    echo "[ERRO] Nao foi possivel criar o projeto Harbor 'poc' (HTTP ${http_code})."
    cat "$response_file" 2>/dev/null || true
    exit 1
    ;;
esac

# Faz os nodes kind resolverem harbor.local no host e permite registry HTTP local.
for node in $(kind get nodes --name poc-devops); do
  gateway=$(docker inspect "$node" --format '{{range .NetworkSettings.Networks}}{{.Gateway}}{{end}}')
  docker exec "$node" sh -c "grep -q '[[:space:]]harbor.local$' /etc/hosts || echo '${gateway} harbor.local' >> /etc/hosts"
  docker exec "$node" mkdir -p /etc/containerd/certs.d/harbor.local
  cat <<'HOSTS' | docker exec -i "$node" sh -c 'cat > /etc/containerd/certs.d/harbor.local/hosts.toml'
server = "http://harbor.local"

[host."http://harbor.local"]
  capabilities = ["pull", "resolve"]
HOSTS
done

echo "[OK] Harbor pronto: http://harbor.local  usuario=admin"
echo "[OK] Nodes kind configurados para pull HTTP de harbor.local."
