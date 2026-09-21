#!/usr/bin/env bash
# Aplica as policies do Kyverno (renderiza a chave pública do cosign na policy de verificação).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$ROOT/cosign.pub" ] || { echo "cosign.pub não encontrado — rode 05-cosign-keys.sh"; exit 1; }
kubectl create namespace frontend --dry-run=client -o yaml | kubectl apply -f -

python3 - "$ROOT" <<'PY' | kubectl apply -f -
import sys, pathlib
root = pathlib.Path(sys.argv[1])
pub = (root / "cosign.pub").read_text().strip().splitlines()
indented = "\n".join(" " * 22 + line for line in pub)
tpl = (root / "k8s/kyverno/verify-images.yaml").read_text()
print(tpl.replace("__COSIGN_PUBLIC_KEY__", indented))
PY
kubectl apply -f "$ROOT/k8s/kyverno/disallow-latest-tag.yaml"
kubectl apply -f "$ROOT/k8s/kyverno/require-best-practices.yaml"
kubectl get clusterpolicy
