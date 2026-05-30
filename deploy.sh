#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# deploy.sh — pull latest code and rebuild inside the LXC container
#
# Run this whenever you push changes to the money-app repo:
#   bash deploy.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$SCRIPT_DIR/config.env" ]]; then
  echo "ERROR: config.env not found."
  exit 1
fi
source "$SCRIPT_DIR/config.env"

SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
[[ -n "${PROXMOX_SSH_KEY:-}" ]] && SSH_OPTS+=(-i "$PROXMOX_SSH_KEY")
SSH=("ssh" "${SSH_OPTS[@]}" "$PROXMOX_USER@$PROXMOX_HOST")

echo "=== Deploying money-app → container $CT_ID ==="

# Check container is running
STATUS=$("${SSH[@]}" "pct status $CT_ID 2>/dev/null || echo 'missing'")
if [[ "$STATUS" != "status: running" ]]; then
  echo "ERROR: Container $CT_ID is not running (status: $STATUS)"
  echo "       Start it with: ssh $PROXMOX_USER@$PROXMOX_HOST 'pct start $CT_ID'"
  exit 1
fi

# Push the deploy script and run it
scp "${SSH_OPTS[@]}" \
  "$SCRIPT_DIR/scripts/container-deploy.sh" \
  "$PROXMOX_USER@$PROXMOX_HOST:/tmp/money-deploy.sh"

"${SSH[@]}" "pct push $CT_ID /tmp/money-deploy.sh /tmp/money-deploy.sh"
"${SSH[@]}" "pct exec $CT_ID -- bash /tmp/money-deploy.sh"

CONTAINER_IP=$("${SSH[@]}" "pct exec $CT_ID -- hostname -I 2>/dev/null | awk '{print \$1}'")
echo ""
echo "✓ Live at http://$CONTAINER_IP:$APP_PORT"
