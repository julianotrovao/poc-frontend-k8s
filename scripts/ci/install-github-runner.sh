#!/usr/bin/env bash
# Instala e registra um GitHub Actions self-hosted runner (Ubuntu x64) como serviço systemd.
# Uso:  sudo REPO_URL=https://github.com/<user>/<repo> RUNNER_TOKEN=<token> ./install-github-runner.sh
#   O RUNNER_TOKEN vem de: repo > Settings > Actions > Runners > New self-hosted runner (expira em ~1h).
set -euo pipefail
: "${REPO_URL:?Informe REPO_URL}"
: "${RUNNER_TOKEN:?Informe RUNNER_TOKEN}"
RUNNER_USER="${RUNNER_USER:-github-runner}"
RUNNER_NAME="${RUNNER_NAME:-poc-runner-01}"
RUNNER_LABELS="${RUNNER_LABELS:-poc-k8s}"
RUNNER_DIR="/home/${RUNNER_USER}/actions-runner"

id "$RUNNER_USER" >/dev/null 2>&1 || adduser --disabled-password --gecos "" "$RUNNER_USER"
getent group docker >/dev/null && usermod -aG docker "$RUNNER_USER"

VER="$(curl -sL https://api.github.com/repos/actions/runner/releases/latest | jq -r .tag_name | sed 's/^v//')"
sudo -u "$RUNNER_USER" mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"
sudo -u "$RUNNER_USER" curl -sSLo runner.tgz "https://github.com/actions/runner/releases/download/v${VER}/actions-runner-linux-x64-${VER}.tar.gz"
sudo -u "$RUNNER_USER" tar xzf runner.tgz && rm -f runner.tgz
./bin/installdependencies.sh

sudo -u "$RUNNER_USER" ./config.sh --unattended --replace \
  --url "$REPO_URL" --token "$RUNNER_TOKEN" \
  --name "$RUNNER_NAME" --labels "$RUNNER_LABELS" --work _work

./svc.sh install "$RUNNER_USER"
./svc.sh start
./svc.sh status || true
echo "Runner ${RUNNER_NAME} registrado com labels: self-hosted,linux,x64,${RUNNER_LABELS}"
