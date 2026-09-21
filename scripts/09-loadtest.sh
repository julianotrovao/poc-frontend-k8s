#!/usr/bin/env bash
# Teste de carga com k6 (300 VUs). Requer Docker.
# K6_PROMETHEUS=true envia métricas do k6 ao Prometheus existente (exige --web.enable-remote-write-receiver nele).
set -euo pipefail
source "$(dirname "$0")/env.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE_URL="${BASE_URL:-http://frontend.local}"
OUT_ARGS=()
if [ "${K6_PROMETHEUS:-false}" = "true" ]; then
  OUT_ARGS=(-o experimental-prometheus-rw -e K6_PROMETHEUS_RW_SERVER_URL=${PROM_URL}/api/v1/write
            -e K6_PROMETHEUS_RW_TREND_STATS="p(95),p(99),avg,max")
fi
docker run --rm -i \
  --add-host "frontend.local:${MASTER_IP}" \
  -e BASE_URL="${BASE_URL}" \
  -v "$ROOT/loadtest:/scripts:ro" \
  grafana/k6 run "${OUT_ARGS[@]}" --summary-export=/dev/stdout /scripts/k6-300vu.js | tee "$ROOT/evidencias/k6-summary.txt"
