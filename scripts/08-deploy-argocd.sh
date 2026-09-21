#!/usr/bin/env bash
# Registra a Application no ArgoCD EXISTENTE (https://201.23.88.239:30085).
# Pré-requisito: o ArgoCD gerencia ESTE cluster (destination https://kubernetes.default.svc).
# Se o ArgoCD estiver em outro cluster, registre este antes:  argocd cluster add <contexto>
#   e troque destination.server em argocd/application.yaml pela URL do cluster registrado.
set -euo pipefail
source "$(dirname "$0")/env.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
grep -q '<SEU-USUARIO>' "$ROOT/argocd/application.yaml" && { echo "Edite argocd/application.yaml (repoURL) primeiro."; exit 1; }

if [ "${ARGOCD_MODE:-kubectl}" = "cli" ]; then
  : "${ARGOCD_PASSWORD:?Defina ARGOCD_PASSWORD}"
  argocd login "${ARGOCD_SERVER}" --insecure --username "${ARGOCD_USER:-admin}" --password "${ARGOCD_PASSWORD}"
  argocd app create -f "$ROOT/argocd/application.yaml" --upsert
  argocd app get frontend
else
  kubectl -n "${ARGOCD_NS}" apply -f "$ROOT/argocd/application.yaml"
  kubectl -n "${ARGOCD_NS}" get applications
fi
echo "UI: https://${ARGOCD_SERVER}/applications/${ARGOCD_NS}/frontend"
