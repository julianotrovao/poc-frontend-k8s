#!/usr/bin/env bash
# Espera o ArgoCD aplicar o digest novo e o canary concluir. Uso: ./wait-rollout.sh sha256:...
set -euo pipefail
DIGEST="${1:?Informe o digest}"
NS="${APP_NS:-frontend}"
for i in $(seq 1 60); do
  IMG="$(kubectl -n "$NS" get rollout frontend -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)"
  if [[ "$IMG" == *"$DIGEST"* ]]; then
    echo "ArgoCD aplicou a nova imagem: $IMG"
    kubectl argo rollouts status frontend -n "$NS" --timeout 600s
    exit $?
  fi
  echo "aguardando ArgoCD sincronizar ($i/60)..."; sleep 10
done
echo "Timeout aguardando o ArgoCD"; exit 1
