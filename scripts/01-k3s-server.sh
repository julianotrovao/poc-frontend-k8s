#!/usr/bin/env bash
# Executar na VM MASTER (Ubuntu 22.04/24.04) como usuário com sudo.
set -euo pipefail
source "$(dirname "$0")/env.sh"

# 1) Resolução de nomes local e registry inseguro (Harbor em HTTP)
grep -q 'harbor.local' /etc/hosts || echo "${HOSTS_LINE}" | sudo tee -a /etc/hosts

sudo mkdir -p /etc/rancher/k3s
sudo tee /etc/rancher/k3s/registries.yaml >/dev/null <<YAML
mirrors:
  "harbor.local":
    endpoint:
      - "http://harbor.local"
YAML

# 2) k3s server: sem Traefik (usaremos ingress-nginx, necessário p/ canary por peso)
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --disable traefik --write-kubeconfig-mode 644 --tls-san ${MASTER_IP}" sh -

# 3) kubeconfig para o usuário atual
mkdir -p "$HOME/.kube"
sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
sed -i "s/127.0.0.1/${MASTER_IP}/" "$HOME/.kube/config"

echo "Token para os workers:"
sudo cat /var/lib/rancher/k3s/server/node-token
kubectl get nodes -o wide
