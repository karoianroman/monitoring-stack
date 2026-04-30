#!/bin/bash
set -euo pipefail

LOG="/var/log/startup.log"
exec > >(tee -a "$LOG") 2>&1

echo "=== Startup script started: $(date) ==="

# ── 1. System update ──────────────────────────────────────────────
apt-get update -y
apt-get install -y ca-certificates curl git

# ── 2. Install Docker ─────────────────────────────────────────────
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
  -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

systemctl enable docker
systemctl start docker

# ── 3. Clone project ──────────────────────────────────────────────
REPO_URL="https://github.com/karoianroman/monitoring-stack.git"
APP_DIR="/opt/monitoring-stack"

git clone "$REPO_URL" "$APP_DIR" || {
  echo "Git clone failed, creating directory structure manually"
  mkdir -p "$APP_DIR"
}

# ── 4. Start the stack ────────────────────────────────────────────
cd "$APP_DIR/monitoring"
docker compose up -d --build

echo "=== Stack started: $(date) ==="
echo "Grafana:    http://$(curl -s ifconfig.me):3000"
echo "Prometheus: http://$(curl -s ifconfig.me):9090"
echo "FastAPI:    http://$(curl -s ifconfig.me):8000"
