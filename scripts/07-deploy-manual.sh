#!/usr/bin/env bash
# Deploy MANUAL (sem pipeline nem ArgoCD): build -> push -> assinar -> helm/kubectl.
# Uso: TAG=1.0.0 ./07-deploy-manual.sh [helm|kubectl]
set -euo pipefail
source "$(dirname "$0")/env.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-helm}"
TAG="${TAG:?Informe TAG, ex.: TAG=1.0.0}"
IMAGE="${REGISTRY}/${HARBOR_PROJECT}/${IMAGE_NAME}"

docker build -t "${IMAGE}:${TAG}" --build-arg APP_VERSION="${TAG}" "$ROOT/app"
docker login "${REGISTRY}" -u admin -p "${HARBOR_ADMIN_PASSWORD}"
docker push "${IMAGE}:${TAG}"
DIGEST="$(docker inspect --format '{{index .RepoDigests 0}}' "${IMAGE}:${TAG}" | cut -d@ -f2)"
echo "digest: ${DIGEST}"

: "${COSIGN_PASSWORD:?Defina COSIGN_PASSWORD}"
cosign sign --yes --key "$ROOT/cosign.key" --tlog-upload=false --allow-insecure-registry "${IMAGE}@${DIGEST}"
cosign verify --key "$ROOT/cosign.pub" --insecure-ignore-tlog=true --allow-insecure-registry "${IMAGE}@${DIGEST}"

kubectl create namespace "${APP_NS}" --dry-run=client -o yaml | kubectl apply -f -
if [ "${MODE}" = "helm" ]; then
  helm upgrade --install frontend "$ROOT/chart/frontend" -n "${APP_NS}" \
    --set image.tag="${TAG}" --set image.digest="${DIGEST}" --wait
else
  # "via kubectl": renderiza o chart e aplica os manifestos puros
  helm template frontend "$ROOT/chart/frontend" -n "${APP_NS}" \
    --set image.tag="${TAG}" --set image.digest="${DIGEST}" | kubectl apply -n "${APP_NS}" -f -
  kubectl -n "${APP_NS}" rollout status deploy/frontend --timeout=180s
fi
kubectl -n "${APP_NS}" get deploy,po,svc,ingress,hpa
curl -s "http://frontend.local/healthz" || true
