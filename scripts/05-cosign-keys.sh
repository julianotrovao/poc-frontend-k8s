#!/usr/bin/env bash
# Gera o par de chaves do cosign. Requer cosign v2.x instalado (scripts/ci/install-ci-tools.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
: "${COSIGN_PASSWORD:?Defina COSIGN_PASSWORD (senha da chave privada)}"
[ -f cosign.key ] && { echo "cosign.key já existe — nada a fazer."; exit 0; }
cosign generate-key-pair
echo
echo "1) COMMITE cosign.pub  (chave pública — usada pelo pipeline e pelo Kyverno)"
echo "2) Crie os secrets no GitHub:  COSIGN_PRIVATE_KEY = conteúdo de cosign.key ;  COSIGN_PASSWORD"
echo "3) NÃO commite cosign.key (já está no .gitignore)"
