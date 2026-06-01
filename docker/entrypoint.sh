#!/bin/bash
set -euo pipefail

echo "=== money-app Docker Setup ==="

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL..."
while ! pg_isready -h postgres -U bvmoney &>/dev/null; do
  echo "  PostgreSQL not ready yet..."
  sleep 2
done
echo "  ✓ PostgreSQL is ready"

# Apply database schema
echo "Applying database schema..."
PGPASSWORD="${DB_PASSWORD:-changeme}" psql \
  -h postgres \
  -U bvmoney \
  -d bvmoney \
  -f /opt/money-app/server/schema.sql
echo "  ✓ Schema applied"

# Write server .env file
echo "Writing server .env..."
mkdir -p /opt/money-app/server
cat > /opt/money-app/server/.env << ENV
NODE_ENV=${NODE_ENV:-production}
PORT=3001
DATABASE_URL=postgresql://bvmoney:${DB_PASSWORD:-changeme}@postgres:5432/bvmoney
SESSION_SECRET=${SESSION_SECRET:-$(openssl rand -hex 32)}
ADMIN_EMAIL=${ADMIN_EMAIL:-}
APP_URL=${APP_URL:-}
GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID:-}
GOOGLE_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET:-}
ENV
chmod 600 /opt/money-app/server/.env
echo "  ✓ .env written"

# Generate self-signed certificate if it doesn't exist
if [[ ! -f /etc/nginx/ssl/money-app.crt ]]; then
  echo "Generating self-signed certificate (10-year)..."
  DOMAIN="${DOMAIN:-localhost}"
  SAN="DNS:localhost,IP:127.0.0.1"
  [[ -n "$DOMAIN" ]] && SAN="DNS:$DOMAIN,$SAN"
  
  openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/money-app.key \
    -out    /etc/nginx/ssl/money-app.crt \
    -subj   "/CN=$DOMAIN" \
    -addext "subjectAltName=$SAN" 2>/dev/null
  chmod 600 /etc/nginx/ssl/money-app.key
  echo "  ✓ Certificate generated"
fi

# Start Nginx
echo "Starting Nginx..."
nginx
echo "  ✓ Nginx running on ports 80/443"

# Start API server
echo "Starting API server..."
cd /opt/money-app
node /opt/money-app/server/server.js
