#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# deploy.sh — pull latest code, rebuild image, restart container
# Run from your local machine whenever you want to deploy:
#   bash deploy.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.env"

SSH_OPTS=(-o StrictHostKeyChecking=accept-new)
[[ -n "${VM_SSH_KEY:-}" ]] && SSH_OPTS+=(-i "$VM_SSH_KEY")

echo "=== Deploying money-app to $VM_HOST ==="

# Push latest infra files to the VM
echo "→ Syncing infra files..."
ssh "${SSH_OPTS[@]}" "$VM_USER@$VM_HOST" "mkdir -p $APP_DIR/infra"
scp "${SSH_OPTS[@]}" \
  "$SCRIPT_DIR/Dockerfile" \
  "$SCRIPT_DIR/nginx.conf" \
  "$SCRIPT_DIR/docker-compose.yml" \
  "$VM_USER@$VM_HOST:$APP_DIR/infra/"

# On the VM: pull app code, build image, restart
ssh "${SSH_OPTS[@]}" "$VM_USER@$VM_HOST" bash -s << REMOTE
set -euo pipefail

echo "→ Pulling latest app code..."
cd "$APP_DIR"
git pull --ff-only

echo "→ Building Docker image (this takes ~60s on first run)..."
cd "$APP_DIR/infra"
APP_PORT=${APP_PORT:-8080} docker compose build --no-cache money-app

echo "→ Restarting container..."
APP_PORT=${APP_PORT:-8080} docker compose up -d money-app

echo "→ Cleaning up old images..."
docker image prune -f

echo "✓ Deploy complete"
REMOTE

echo ""
echo "=== App is live at http://$VM_HOST:${APP_PORT:-8080} ==="
