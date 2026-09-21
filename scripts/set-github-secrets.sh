#!/usr/bin/env bash
# Cadastra os secrets do GitHub Actions com o GitHub CLI (gh).  Pré-requisito: `gh auth login`.
# Uso (exporte o que já tem; o que faltar é pedido de forma interativa, sem eco):
#   REPO=<usuario>/poc-frontend-nodejs SONAR_TOKEN=... ./scripts/set-github-secrets.sh
set -euo pipefail
: "${REPO:?Informe REPO=<usuario>/<repositorio>}"
cd "$(dirname "$0")/.."

ask() { # ask NOME [secreto=1]
  local n="$1"
  if [ -z "${!n:-}" ]; then
    if [ "${2:-1}" = 1 ]; then read -r -s -p "$n: " "$n"; echo; else read -r -p "$n: " "$n"; fi
  fi
}

ask SONAR_TOKEN
ask HARBOR_USERNAME 0
ask HARBOR_PASSWORD
ask COSIGN_PASSWORD
ask INGRESS_IP 0

gh secret set SONAR_TOKEN        -R "$REPO" --body "$SONAR_TOKEN"
gh secret set HARBOR_USERNAME    -R "$REPO" --body "$HARBOR_USERNAME"
gh secret set HARBOR_PASSWORD    -R "$REPO" --body "$HARBOR_PASSWORD"
gh secret set COSIGN_PASSWORD    -R "$REPO" --body "$COSIGN_PASSWORD"
gh secret set INGRESS_IP         -R "$REPO" --body "$INGRESS_IP"
[ -f cosign.key ] || { echo "cosign.key não encontrado — rode scripts/05-cosign-keys.sh"; exit 1; }
gh secret set COSIGN_PRIVATE_KEY -R "$REPO" < cosign.key

# Opcionais (sync imediato no ArgoCD a partir do pipeline)
if [ -n "${ARGOCD_AUTH_TOKEN:-}" ]; then
  gh secret set ARGOCD_AUTH_TOKEN -R "$REPO" --body "$ARGOCD_AUTH_TOKEN"
  gh secret set ARGOCD_SERVER     -R "$REPO" --body "${ARGOCD_SERVER:-201.23.88.239:30085}"
fi
gh secret list -R "$REPO"
