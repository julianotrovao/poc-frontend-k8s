#!/usr/bin/env bash
# Variáveis compartilhadas. Copie para scripts/env.local.sh (ignorado pelo Git) para sobrescrever.
export MASTER_IP="${MASTER_IP:-201.23.88.239}"      # IP do nó que recebe o Ingress (ingress-nginx via servicelb)
export CI_IP="${CI_IP:-201.23.88.239}"              # VM do runner + SonarQube (+ k6); ajuste se for outra
export REGISTRY="${REGISTRY:-harbor.local}"
export HARBOR_PROJECT="${HARBOR_PROJECT:-poc}"
export HARBOR_ADMIN_PASSWORD="${HARBOR_ADMIN_PASSWORD:-Harbor12345}"
export IMAGE_NAME="${IMAGE_NAME:-frontend}"
export APP_NS="${APP_NS:-frontend}"

# ---- Stack JÁ EXISTENTE (não é instalada por estes scripts)
export GRAFANA_URL="${GRAFANA_URL:-http://201.23.88.239:30300}"
export PROM_URL="${PROM_URL:-http://201.23.88.239:30900}"
export ARGOCD_SERVER="${ARGOCD_SERVER:-201.23.88.239:30085}"   # https, certificado autoassinado
export ARGOCD_NS="${ARGOCD_NS:-argocd}"
export MONITORING_NS="${MONITORING_NS:-monitoring}"            # namespace onde o blackbox-exporter será instalado

# ---- Loki (único componente de observabilidade instalado pela POC)
export LOKI_NODE="${LOKI_NODE:-}"                    # nome do nó (kubectl get nodes) onde o Loki será fixado
export LOKI_NODEPORT="${LOKI_NODEPORT:-31100}"
export LOKI_URL="${LOKI_URL:-http://loki.logging.svc.cluster.local:3100}"   # URL usada pelo Grafana

# shellcheck disable=SC1091
[ -f "$(dirname "${BASH_SOURCE[0]}")/env.local.sh" ] && source "$(dirname "${BASH_SOURCE[0]}")/env.local.sh"
export HOSTS_LINE="${MASTER_IP} harbor.local frontend.local"
