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

# schema.sql runs as the postgres superuser, so any table/sequence it creates
# is owned by postgres and the app role (bvmoney) has no rights to it. Without
# this the app throws "permission denied for schema public" on any release
# that adds a table. ALTER DEFAULT PRIVILEGES only covers FUTURE objects, so
# the explicit GRANTs are still needed for the ones just created.
echo "── Granting privileges to app role ──────────────────────────"
su -s /bin/bash postgres -c "psql -d bvmoney -c \"
  GRANT USAGE, CREATE ON SCHEMA public TO bvmoney;
  GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO bvmoney;
  GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO bvmoney;
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO bvmoney;
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO bvmoney;
\"" > /dev/null
echo "   ✓ Privileges granted"

echo "── Rebuilding client ────────────────────────────────────────"
npm run build --prefix client

echo "── Updating served files ────────────────────────────────────"
cp -r client/dist/. /var/www/html/

echo "── Restarting API server ────────────────────────────────────"
systemctl restart money-app-api

nginx -s reload

echo ""
echo "✓ Deploy complete"
