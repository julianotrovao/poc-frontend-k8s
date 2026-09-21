#!/usr/bin/env bash
# Instala na VM de CI (Ubuntu) as ferramentas usadas pelo pipeline: docker, trivy, cosign v2, kubectl,
# helm, yq e o plugin argo rollouts.   Uso: sudo -E ./install-ci-tools.sh
set -euo pipefail
COSIGN_VERSION="${COSIGN_VERSION:-v2.4.1}"   # mantenha na linha 2.x (flags --tlog-upload/--allow-insecure-registry)
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y ca-certificates curl gnupg jq git unzip docker.io wget apt-transport-https

# Trivy
wget -qO- https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor -o /usr/share/keyrings/trivy.gpg
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" > /etc/apt/sources.list.d/trivy.list
apt-get update && apt-get install -y trivy

# cosign
curl -sSLo /tmp/cosign.deb "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign_${COSIGN_VERSION#v}_amd64.deb"
dpkg -i /tmp/cosign.deb

# kubectl
KVER="$(curl -sL https://dl.k8s.io/release/stable.txt)"
curl -sSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/${KVER}/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl

# helm
curl -sSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# yq
curl -sSLo /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
chmod +x /usr/local/bin/yq

# kubectl-argo-rollouts (plugin)
curl -sSLo /usr/local/bin/kubectl-argo-rollouts https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
chmod +x /usr/local/bin/kubectl-argo-rollouts

# argocd CLI
curl -sSLo /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd

# argocd CLI (sync/refresh opcional a partir do pipeline)
curl -sSLo /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd

# Docker: aceitar o Harbor em HTTP
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<JSON
{ "insecure-registries": ["harbor.local"] }
JSON
systemctl enable --now docker && systemctl restart docker

true

echo "Versões instaladas:"; trivy --version | head -1; cosign version 2>&1 | grep -i gitversion; kubectl version --client; helm version --short; yq --version
