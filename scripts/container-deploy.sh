#!/bin/bash
# Runs INSIDE the LXC container on every deploy/update.
# Called by deploy.sh via: pct exec <id> -- bash /tmp/money-deploy.sh
set -euo pipefail

echo "── Pulling latest code ──────────────────────────────────────"
cd /opt/money-app
git pull --ff-only

echo "── Updating dependencies ────────────────────────────────────"
npm ci --prefix client --silent
npm ci --prefix server --silent

echo "── Applying schema migrations ───────────────────────────────"
su -s /bin/bash postgres -c "psql -d bvmoney -f /opt/money-app/server/schema.sql"
echo "   ✓ Schema up to date"

echo "── Rebuilding client ────────────────────────────────────────"
npm run build --prefix client

echo "── Updating served files ────────────────────────────────────"
cp -r client/dist/. /var/www/html/

echo "── Restarting API server ────────────────────────────────────"
systemctl restart money-app-api

nginx -s reload

echo ""
echo "✓ Deploy complete"
