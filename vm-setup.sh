#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# vm-setup.sh — one-time setup of the Proxmox VM (Debian/Ubuntu)
# Run this once after creating your VM:
#   bash vm-setup.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.env"

SSH_OPTS=(-o StrictHostKeyChecking=accept-new)
[[ -n "${VM_SSH_KEY:-}" ]] && SSH_OPTS+=(-i "$VM_SSH_KEY")

echo "=== Setting up $VM_USER@$VM_HOST ==="

ssh "${SSH_OPTS[@]}" "$VM_USER@$VM_HOST" bash -s << 'REMOTE'
set -euo pipefail

# ── Install Docker ───────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
  echo "→ Installing Docker..."
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
  systemctl enable --now docker
  echo "✓ Docker $(docker --version)"
else
  echo "✓ Docker already installed: $(docker --version)"
fi

# ── Install git ───────────────────────────────────────────────────────────────
command -v git &>/dev/null || apt-get install -y -qq git

# ── Firewall: open app port ──────────────────────────────────────────────────
if command -v ufw &>/dev/null; then
  ufw allow 8080/tcp 2>/dev/null || true
fi

echo "=== VM setup complete ==="
REMOTE

# ── Clone repos on VM ────────────────────────────────────────────────────────
echo "→ Cloning app repo to $APP_DIR..."
ssh "${SSH_OPTS[@]}" "$VM_USER@$VM_HOST" bash -s <<REMOTE
set -euo pipefail
if [ -d "$APP_DIR/.git" ]; then
  cd "$APP_DIR" && git pull --ff-only
else
  git clone "$APP_REPO" "$APP_DIR"
fi

# Copy infra files into the repo so docker-compose can find them
mkdir -p "$APP_DIR/infra"
REMOTE

echo "→ Uploading infra files..."
scp "${SSH_OPTS[@]}" \
  "$SCRIPT_DIR/Dockerfile" \
  "$SCRIPT_DIR/nginx.conf" \
  "$SCRIPT_DIR/docker-compose.yml" \
  "$VM_USER@$VM_HOST:$APP_DIR/infra/"

echo "→ Running initial deploy..."
bash "$SCRIPT_DIR/deploy.sh"

echo ""
echo "=== Done! App is at http://$VM_HOST:${APP_PORT:-8080} ==="
