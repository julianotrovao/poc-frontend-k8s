#!/usr/bin/env bash
# Gera k8s/observability/prometheus-fallback/frontend-rules.yml (SLIs + alertas) a partir do chart,
# para Prometheus SEM Operator (incluir em rule_files). Requer helm e yq.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
helm template frontend "$ROOT/chart/frontend" -n frontend -s templates/prometheusrule.yaml \
  | yq '{"groups": .spec.groups}' > "$ROOT/k8s/observability/prometheus-fallback/frontend-rules.yml"
echo "gerado: k8s/observability/prometheus-fallback/frontend-rules.yml"
