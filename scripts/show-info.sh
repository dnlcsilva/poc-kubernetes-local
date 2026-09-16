#!/usr/bin/env bash
set -euo pipefail

decode_secret() {
  local namespace=$1 secret=$2 key=$3
  kubectl get secret "$secret" -n "$namespace" \
    -o "jsonpath={.data.${key}}" 2>/dev/null | base64 -d
}

jenkins_user=$(docker inspect poc-jenkins \
  --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null \
  | sed -n 's/^JENKINS_ADMIN_USER=//p' || true)
jenkins_password=$(docker inspect poc-jenkins \
  --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null \
  | sed -n 's/^JENKINS_ADMIN_PASSWORD=//p' || true)
harbor_password=$(decode_secret harbor harbor-core HARBOR_ADMIN_PASSWORD || true)
grafana_user=$(decode_secret monitoring monitoring-grafana admin-user || true)
grafana_password=$(decode_secret monitoring monitoring-grafana admin-password || true)
argocd_password=$(decode_secret argocd argocd-initial-admin-secret password || true)

if [[ -n "$argocd_password" ]]; then
  if kubectl get application poc-app -n argocd >/dev/null 2>&1; then
    argocd_access="http://argocd.local    admin / ${argocd_password}  (CD ativo)"
  else
    argocd_access="http://argocd.local    admin / ${argocd_password}  (sem Application)"
  fi
else
  argocd_access='nao instalado (execute: make argocd)'
fi

cat <<OUT

==========================================================================
 POC Kubernetes Local - acessos
==========================================================================
 Aplicacao : http://poc.local
 Jenkins   : http://localhost:8080  ${jenkins_user:-admin} / ${jenkins_password:-indisponivel}
 SonarQube : http://localhost:9000  admin / admin (primeiro acesso)
 Harbor    : http://harbor.local    admin / ${harbor_password:-indisponivel}
 Grafana   : http://grafana.local   ${grafana_user:-admin} / ${grafana_password:-indisponivel}
 Prometheus: http://prometheus.local sem autenticacao
 Argo CD   : ${argocd_access}
==========================================================================

Este comando exibe segredos no terminal. Nao copie a saida para logs,
issues, screenshots ou arquivos versionados.
OUT
