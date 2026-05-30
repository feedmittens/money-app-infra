#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# lxc-setup.sh — one-time setup of an LXC container on Proxmox
#
# What it does:
#   1. SSHes into your Proxmox host
#   2. Downloads a Debian 12 LXC template (if not already cached)
#   3. Creates and starts the container
#   4. Installs Nginx + Node.js inside it
#   5. Clones and builds the app
#   6. Prints the URL when done
#
# Usage:
#   cp config.env.example config.env   # fill in your values first
#   bash lxc-setup.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$SCRIPT_DIR/config.env" ]]; then
  echo "ERROR: config.env not found. Copy config.env.example and fill it in."
  exit 1
fi
source "$SCRIPT_DIR/config.env"

# Build SSH options
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
[[ -n "${PROXMOX_SSH_KEY:-}" ]] && SSH_OPTS+=(-i "$PROXMOX_SSH_KEY")
SSH=("ssh" "${SSH_OPTS[@]}" "$PROXMOX_USER@$PROXMOX_HOST")

echo "=== money-app LXC setup ==="
echo "    Proxmox host : $PROXMOX_HOST"
echo "    Container ID : $CT_ID ($CT_HOSTNAME)"
echo "    Storage      : $CT_STORAGE"
echo "    Network IP   : $CT_IP"
echo ""

# ── 1. Create the container on the Proxmox host ────────────────────────────
echo "→ Step 1/3: Creating container on Proxmox..."

"${SSH[@]}" bash -s << PROXMOX
set -euo pipefail

# Check if container already exists
if pct status $CT_ID &>/dev/null; then
  echo "   Container $CT_ID already exists — skipping creation"
else
  # Download Debian 12 template if needed
  echo "   Updating template list..."
  pveam update >/dev/null

  TEMPLATE=\$(pveam available --section system 2>/dev/null \
    | awk '/debian-12-standard/{print \$2}' | sort -V | tail -1)

  if [[ -z "\$TEMPLATE" ]]; then
    echo "ERROR: No debian-12-standard template found. Check: pveam available --section system"
    exit 1
  fi
  echo "   Template: \$TEMPLATE"

  if ! pveam list local 2>/dev/null | grep -q "\$TEMPLATE"; then
    echo "   Downloading template (may take a minute)..."
    pveam download local "\$TEMPLATE"
  fi

  # Build net0 string
  if [[ "$CT_IP" == "dhcp" ]]; then
    NET="name=eth0,bridge=$CT_BRIDGE,ip=dhcp"
  else
    NET="name=eth0,bridge=$CT_BRIDGE,ip=$CT_IP,gw=$CT_GW"
  fi

  echo "   Creating container..."
  pct create $CT_ID "local:vztmpl/\$TEMPLATE" \
    --hostname "$CT_HOSTNAME" \
    --cores    $CT_CORES \
    --memory   $CT_MEMORY \
    --swap     512 \
    --rootfs   "$CT_STORAGE:8" \
    --net0     "\$NET" \
    --unprivileged 1 \
    --onboot   1

  echo "   ✓ Container $CT_ID created"
fi

# Start if not running
if [[ "\$(pct status $CT_ID)" != "status: running" ]]; then
  echo "   Starting container..."
  pct start $CT_ID
  echo "   Waiting for network..."
  sleep 8
fi

echo "   ✓ Container is running"
PROXMOX

# ── 2. Push the init script into the container ─────────────────────────────
echo "→ Step 2/3: Uploading setup script..."

# Copy script to Proxmox host first, then pct push into container
scp "${SSH_OPTS[@]}" \
  "$SCRIPT_DIR/scripts/container-init.sh" \
  "$PROXMOX_USER@$PROXMOX_HOST:/tmp/money-init.sh"

"${SSH[@]}" "pct push $CT_ID /tmp/money-init.sh /tmp/money-init.sh"
echo "   ✓ Script uploaded"

# ── 3. Run the init script inside the container ────────────────────────────
echo "→ Step 3/3: Installing and building inside container (takes ~2 min)..."
echo ""

"${SSH[@]}" \
  "pct exec $CT_ID -- env APP_PORT='$APP_PORT' APP_REPO='$APP_REPO' GITHUB_TOKEN='${GITHUB_TOKEN:-}' bash /tmp/money-init.sh"

# ── Done ───────────────────────────────────────────────────────────────────
CONTAINER_IP=$("${SSH[@]}" "pct exec $CT_ID -- hostname -I 2>/dev/null | awk '{print \$1}'")

echo ""
echo "════════════════════════════════════════"
echo "  ✓ Setup complete!"
echo ""
echo "  Open in browser:"
echo "  http://$CONTAINER_IP:$APP_PORT"
echo ""
echo "  To update the app later:"
echo "  bash deploy.sh"
echo "════════════════════════════════════════"
