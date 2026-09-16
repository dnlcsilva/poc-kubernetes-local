#!/usr/bin/env bash
set -euo pipefail

INGRESS_NGINX_CHART_VERSION=4.15.1
METRICS_SERVER_CHART_VERSION=3.14.0
KUBE_PROMETHEUS_STACK_CHART_VERSION=91.3.0
LOKI_CHART_VERSION=18.13.1
PROMTAIL_CHART_VERSION=6.17.1
KYVERNO_CHART_VERSION=3.9.1

add_repo() {
  local name=$1 url=$2
  helm repo add "$name" "$url" --force-update >/dev/null
}

add_repo ingress-nginx https://kubernetes.github.io/ingress-nginx
add_repo metrics-server https://kubernetes-sigs.github.io/metrics-server/
add_repo prometheus-community https://prometheus-community.github.io/helm-charts
add_repo grafana https://grafana.github.io/helm-charts
add_repo grafana-community https://grafana-community.github.io/helm-charts
add_repo kyverno https://kyverno.github.io/kyverno/
helm repo update >/dev/null

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --version "$INGRESS_NGINX_CHART_VERSION" \
  -n ingress-nginx --create-namespace \
  --set controller.hostPort.enabled=true \
  --set controller.service.type=ClusterIP \
  --set controller.nodeSelector."kubernetes\.io/hostname"=poc-devops-control-plane \
  --set 'controller.tolerations[0].key=node-role.kubernetes.io/control-plane' \
  --set 'controller.tolerations[0].operator=Exists' \
  --set 'controller.tolerations[0].effect=NoSchedule' \
  --wait --timeout 10m

helm upgrade --install metrics-server metrics-server/metrics-server \
  --version "$METRICS_SERVER_CHART_VERSION" \
  -n kube-system \
  --set 'args[0]=--kubelet-insecure-tls' \
  --wait --timeout 5m

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --version "$KUBE_PROMETHEUS_STACK_CHART_VERSION" \
  -n monitoring --create-namespace \
  --set grafana.defaultDashboardsEnabled=false \
  --set kubeControllerManager.enabled=false \
  --set kubeEtcd.enabled=false \
  --set kubeProxy.enabled=false \
  --set kubeScheduler.enabled=false \
  --wait --timeout 15m

helm upgrade --install loki grafana-community/loki \
  --version "$LOKI_CHART_VERSION" \
  -n monitoring \
  --set deploymentMode=Monolithic \
  --set loki.auth_enabled=false \
  --set loki.commonConfig.replication_factor=1 \
  --set loki.storage.type=filesystem \
  --set loki.useTestSchema=true \
  --set singleBinary.replicas=1 \
  --set singleBinary.persistence.enabled=false \
  --set backend.replicas=0 \
  --set read.replicas=0 \
  --set write.replicas=0 \
  --set gateway.enabled=false \
  --set chunksCache.enabled=false \
  --set resultsCache.enabled=false \
  --set lokiCanary.enabled=false \
  --set test.enabled=false \
  --wait --timeout 10m

helm upgrade --install promtail grafana/promtail \
  --version "$PROMTAIL_CHART_VERSION" \
  -n monitoring \
  --set 'config.clients[0].url=http://loki:3100/loki/api/v1/push' \
  --set serviceMonitor.enabled=false \
  --wait --timeout 10m

kubectl apply -k kubernetes/monitoring/

helm upgrade --install kyverno kyverno/kyverno \
  --version "$KYVERNO_CHART_VERSION" \
  -n kyverno --create-namespace \
  --wait --timeout 10m

kubectl rollout status deployment/kyverno-admission-controller \
  -n kyverno --timeout=5m

policy_applied=0
for _ in $(seq 1 30); do
  if kubectl apply -f kubernetes/kyverno/disallow-latest.yaml; then
    policy_applied=1
    break
  fi
  sleep 2
done

if (( ! policy_applied )); then
  echo '[ERRO] O webhook do Kyverno nao ficou pronto para receber a policy.' >&2
  exit 1
fi

echo "[OK] Ingress, Metrics Server, Prometheus/Grafana, Loki/Promtail e Kyverno instalados."
