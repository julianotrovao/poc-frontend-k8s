#!/usr/bin/env bash
# Executar em CADA worker. Uso: K3S_TOKEN=<token> ./02-k3s-agent.sh
set -euo pipefail
source "$(dirname "$0")/env.sh"
: "${K3S_TOKEN:?Informe K3S_TOKEN (cat /var/lib/rancher/k3s/server/node-token no master)}"

grep -q 'harbor.local' /etc/hosts || echo "${HOSTS_LINE}" | sudo tee -a /etc/hosts
sudo mkdir -p /etc/rancher/k3s
sudo tee /etc/rancher/k3s/registries.yaml >/dev/null <<YAML
mirrors:
  "harbor.local":
    endpoint:
      - "http://harbor.local"
YAML

curl -sfL https://get.k3s.io | K3S_URL="https://${MASTER_IP}:6443" K3S_TOKEN="${K3S_TOKEN}" sh -
