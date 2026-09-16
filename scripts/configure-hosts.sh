#!/usr/bin/env bash
set -euo pipefail

hosts=(poc.local harbor.local grafana.local prometheus.local argocd.local)
missing=()

for host in "${hosts[@]}"; do
  if ! grep -Eq "(^|[[:space:]])${host//./\\.}([[:space:]]|$)" /etc/hosts; then
    missing+=("$host")
  fi
done

if (( ${#missing[@]} == 0 )); then
  echo '[OK] Hosts locais ja existem em /etc/hosts.'
  exit 0
fi

line="127.0.0.1 ${missing[*]}"
echo "[INFO] Sera adicionada a linha: ${line}"
printf '%s\n' "$line" | sudo tee -a /etc/hosts >/dev/null
echo '[OK] /etc/hosts atualizado.'
