#!/usr/bin/env bash
# Cria o projeto "poc" (privado) no Harbor via API.
set -euo pipefail
source "$(dirname "$0")/env.sh"
curl -sf -u "admin:${HARBOR_ADMIN_PASSWORD}" -H 'Content-Type: application/json' \
  -X POST "http://${REGISTRY}/api/v2.0/projects" \
  -d "{\"project_name\":\"${HARBOR_PROJECT}\",\"public\":false}" && echo "projeto criado" || echo "projeto já existe (ou erro — verifique)"
echo "Agora crie uma Robot Account em Harbor > Projects > ${HARBOR_PROJECT} > Robot Accounts (push/pull) e guarde nos secrets do GitHub."
