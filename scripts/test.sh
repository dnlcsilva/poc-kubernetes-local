#!/usr/bin/env bash
set -euo pipefail

VENV=.venv
python3 -m venv "$VENV"
# shellcheck disable=SC1091
source "$VENV/bin/activate"
python -m pip install --quiet --upgrade pip
python -m pip install --quiet -r app/requirements-dev.txt
(
  cd app
  coverage_file=$(mktemp /tmp/poc-coverage.XXXXXX)
  trap 'rm -f "$coverage_file"' EXIT
  PYTHONDONTWRITEBYTECODE=1 COVERAGE_FILE="$coverage_file" \
    python -m pytest -q -p no:cacheprovider --cov=main --cov-report=term-missing
)
helm lint helm/poc-app
for dashboard in kubernetes/monitoring/dashboards/*.json; do
  python -m json.tool "$dashboard" >/dev/null
done
kubectl kustomize kubernetes/monitoring >/dev/null
python -c 'import pathlib, yaml; [list(yaml.safe_load_all(path.read_text())) for path in pathlib.Path("kubernetes/argocd").glob("*.yaml")]'

echo '[OK] Unit tests, helm lint e manifests Kubernetes passaram.'
