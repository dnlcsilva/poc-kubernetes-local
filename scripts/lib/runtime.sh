#!/usr/bin/env bash

runtime_base=${XDG_RUNTIME_DIR:-/tmp}
POC_RUNTIME_DIR=${POC_RUNTIME_DIR:-${runtime_base}/poc-kubernetes-local-${UID}}
POC_KUBECONFIG_PATH=${POC_KUBECONFIG_PATH:-${POC_RUNTIME_DIR}/kubeconfig}

prepare_runtime_dir() {
  mkdir -p "$POC_RUNTIME_DIR"
  chmod 700 "$POC_RUNTIME_DIR"
}
