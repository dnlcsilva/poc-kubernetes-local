#!/usr/bin/env bash
set -euo pipefail

: "${REPO_URL:?Informe o repositorio: make argocd REPO_URL=https://...}"

if [[ "$REPO_URL" =~ ^https?://[^/]*@ ]]; then
  echo '[ERRO] Nao informe credenciais dentro da URL do repositorio.' >&2
  exit 1
fi

current_image=$(kubectl get deployment poc-app -n poc \
  -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)
if [[ -z "$current_image" || "$current_image" != *:* ]]; then
  echo '[ERRO] Aplicacao principal nao encontrada. Execute make up primeiro.' >&2
  exit 1
fi
image_repository=${current_image%:*}
image_tag=${current_image##*:}

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side --force-conflicts \
  -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.3/manifests/install.yaml

kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge \
  -p '{"data":{"server.insecure":"true"}}'
kubectl apply -f kubernetes/argocd/ingress.yaml
kubectl rollout restart deployment/argocd-server -n argocd
kubectl rollout status deployment --all -n argocd --timeout=10m
kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=10m

repo_url_escaped=${REPO_URL//&/\\&}
image_repository_escaped=${image_repository//&/\\&}
image_tag_escaped=${image_tag//&/\\&}
application_manifest=$(mktemp /tmp/poc-argocd-application.XXXXXX.yaml)
trap 'rm -f "$application_manifest"' EXIT
sed \
  -e "s|REPLACE_WITH_YOUR_GIT_REPOSITORY|${repo_url_escaped}|" \
  -e "s|REPLACE_WITH_IMAGE_REPOSITORY|${image_repository_escaped}|" \
  -e "s|REPLACE_WITH_IMAGE_TAG|${image_tag_escaped}|" \
  kubernetes/argocd/application.yaml >"$application_manifest"
kubectl apply -f "$application_manifest"

echo '[INFO] Aguardando sincronizacao inicial do Argo CD...'
for _ in $(seq 1 120); do
  sync_status=$(kubectl get application poc-app -n argocd \
    -o jsonpath='{.status.sync.status}' 2>/dev/null || true)
  health_status=$(kubectl get application poc-app -n argocd \
    -o jsonpath='{.status.health.status}' 2>/dev/null || true)
  if [[ "$sync_status" == 'Synced' && "$health_status" == 'Healthy' ]]; then
    echo '[OK] Aplicacao Synced e Healthy.'
    break
  fi
  sleep 5
done

if [[ "${sync_status:-}" != 'Synced' || "${health_status:-}" != 'Healthy' ]]; then
  echo '[ERRO] O Argo CD nao concluiu a sincronizacao inicial.' >&2
  kubectl get application poc-app -n argocd -o wide >&2 || true
  exit 1
fi

echo "[OK] Argo CD instalado: http://argocd.local"
echo '[OK] Argo CD agora e o unico responsavel pelo deploy no Kubernetes.'
echo '[OK] Jenkins permanece responsavel por testes, analises, build e push.'
