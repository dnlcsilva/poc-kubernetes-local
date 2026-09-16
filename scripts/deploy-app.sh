#!/usr/bin/env bash
set -euo pipefail

TAG=${1:-1.0.0}
IMAGE="poc-app:${TAG}"

if kubectl get application poc-app -n argocd >/dev/null 2>&1; then
  echo '[ERRO] Modo GitOps ativo. O deploy deve ser realizado pelo Argo CD.' >&2
  exit 1
fi

echo "[INFO] Build local: ${IMAGE}"
docker build -t "$IMAGE" app
kind load docker-image "$IMAGE" --name poc-devops

helm upgrade --install poc-app helm/poc-app \
  -n poc --create-namespace \
  --set image.repository=poc-app \
  --set image.tag="$TAG" \
  --set image.pullPolicy=IfNotPresent \
  --wait --timeout 5m

kubectl rollout status deployment/poc-app -n poc --timeout=180s

printf '[INFO] Validando /healthz'
for _ in $(seq 1 30); do
  if curl -fsS -H 'Host: poc.local' http://127.0.0.1/healthz >/tmp/poc-healthz.json 2>/dev/null; then
    echo
    cat /tmp/poc-healthz.json
    echo
    echo "[OK] Aplicacao respondendo pelo Ingress."
    exit 0
  fi
  printf '.'
  sleep 2
done

echo
echo "[ERRO] /healthz nao respondeu dentro do tempo esperado."
kubectl get pods -n poc -o wide || true
kubectl get ingress -n poc || true
exit 1
