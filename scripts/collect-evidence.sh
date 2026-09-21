#!/usr/bin/env bash
# Coleta as evidências (saídas de kubectl/helm/argo) em evidencias/output/.  Anexe prints da UI junto.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/evidencias/output"; mkdir -p "$OUT"
run() { local f="$1"; shift; { echo "\$ $*"; "$@" 2>&1; } | tee "$OUT/$f.txt" >/dev/null; echo "ok  $f"; }
run 01-nodes            kubectl get nodes -o wide
run 02-platform-pods    kubectl get pods -A
run 03-ingress          kubectl get ingress -A
run 04-helm-releases    helm list -A
run 05-app-resources    kubectl -n frontend get deploy,rollout,po,svc,ingress,hpa,cm,secret
run 06-argocd-app       kubectl -n argocd get applications
run 07-rollout-status   kubectl argo rollouts get rollout frontend -n frontend
run 08-hpa              kubectl -n frontend get hpa
run 09-policies         kubectl get clusterpolicy
run 10-policy-reports   kubectl get policyreport -A
run 11-monitoring       kubectl get podmonitor,probe,prometheusrule -A
run 12-healthz          curl -si http://frontend.local/healthz
run 13-deny-latest      kubectl apply -f "$ROOT/examples/pod-latest.yaml"
run 14-deny-unsigned    kubectl apply -f "$ROOT/examples/pod-unsigned.yaml"
run 15-events           kubectl -n frontend get events --sort-by=.lastTimestamp
echo "Saídas em $OUT"
