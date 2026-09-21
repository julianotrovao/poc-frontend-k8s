#!/usr/bin/env bash
# Instala no cluster: ingress-nginx, Harbor, blackbox-exporter, Loki+Promtail (Loki em nó específico),
# Kyverno e Argo Rollouts.
# NÃO instala Prometheus/Grafana/ArgoCD: a POC se integra aos já existentes (ver env.sh).
# Uso: LOKI_NODE=<nome-do-no> ./03-install-platform.sh
set -euo pipefail
source "$(dirname "$0")/env.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${LOKI_NODE:?Defina LOKI_NODE com o nome do nó do Loki (kubectl get nodes)}"
kubectl get node "$LOKI_NODE" >/dev/null

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add harbor https://helm.goharbor.io
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

echo "==> Pré-checagem: Prometheus Operator (CRDs) no cluster?"
if kubectl get crd podmonitors.monitoring.coreos.com probes.monitoring.coreos.com prometheusrules.monitoring.coreos.com >/dev/null 2>&1; then
  echo "    CRDs presentes -> o chart usa PodMonitor/Probe/PrometheusRule (monitoring.enabled=true)"
else
  echo "    CRDs AUSENTES -> use monitoring.enabled=false e o fallback em k8s/observability/prometheus-fallback/"
fi

echo "==> CoreDNS: resolver harbor.local dentro do cluster"
kubectl apply -f - <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  poc-hosts.override: |
    hosts {
      ${MASTER_IP} harbor.local frontend.local
      fallthrough
    }
YAML
kubectl -n kube-system rollout restart deploy/coredns

echo "==> ingress-nginx"
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace \
  -f "$ROOT/k8s/ingress-nginx/values.yaml" --wait

echo "==> Harbor"
helm upgrade --install harbor harbor/harbor -n harbor --create-namespace \
  -f "$ROOT/k8s/harbor/values.yaml" --set harborAdminPassword="${HARBOR_ADMIN_PASSWORD}" --timeout 10m --wait

echo "==> blackbox-exporter (sonda do /healthz; namespace monitoring)"
helm upgrade --install prometheus-blackbox-exporter prometheus-community/prometheus-blackbox-exporter \
  -n monitoring --create-namespace --wait

echo "==> Loki fixado no nó ${LOKI_NODE}"
kubectl label node "$LOKI_NODE" poc/loki=true --overwrite
helm upgrade --install loki grafana/loki-stack -n logging --create-namespace \
  -f "$ROOT/k8s/observability/values-loki-stack.yaml" --wait
kubectl -n logging get pods -o wide

echo "==> Kyverno (allowInsecureRegistry por causa do Harbor em HTTP)"
helm upgrade --install kyverno kyverno/kyverno -n kyverno --create-namespace \
  -f "$ROOT/k8s/kyverno/kyverno-values.yaml" --wait

echo "==> Argo Rollouts (canary) — o ArgoCD já existente gerencia o Rollout"
kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

cat <<MSG

Próximos passos de integração:
  ./scripts/10-grafana-integration.sh     # datasource Loki + dashboard SLO no seu Grafana (${GRAFANA_URL})
  ./scripts/08-deploy-argocd.sh     # Application no seu ArgoCD (https://${ARGOCD_SERVER})
MSG
