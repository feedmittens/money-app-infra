#!/bin/bash
# Runs INSIDE the LXC container on every deploy/update.
# Called by deploy.sh via: pct exec <id> -- bash /tmp/money-deploy.sh
set -euo pipefail

echo "── Pulling latest code ──────────────────────────────────────"
cd /opt/money-app
git pull --ff-only

echo "── Rebuilding app ───────────────────────────────────────────"
mkdir -p client/public
npm ci --prefix client --silent
npm run build --prefix client

echo "── Updating served files ────────────────────────────────────"
cp -r client/dist/. /var/www/html/
nginx -s reload

echo ""
echo "✓ Deploy complete"
