#!/bin/bash
# Runs INSIDE the LXC container on first setup.
# Called by lxc-setup.sh via: pct exec <id> -- env VAR=val bash /tmp/money-init.sh
set -euo pipefail

APP_REPO="${APP_REPO:-https://github.com/feedmittens/money-app.git}"
APP_PORT="${APP_PORT:-8080}"

echo "── Installing packages ──────────────────────────────────────"
apt-get update -qq
apt-get install -y -qq curl git nginx ca-certificates

echo "── Installing Node.js 22 ────────────────────────────────────"
if ! command -v node &>/dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - 2>/dev/null
  apt-get install -y -qq nodejs
fi
echo "   node $(node --version) / npm $(npm --version)"

echo "── Cloning app ──────────────────────────────────────────────"
if [ -d /opt/money-app/.git ]; then
  cd /opt/money-app
  git pull --ff-only
else
  git clone "$APP_REPO" /opt/money-app
fi

echo "── Building app ─────────────────────────────────────────────"
cd /opt/money-app
mkdir -p client/public
npm ci --prefix client --silent
npm run build --prefix client

mkdir -p /var/www/html
cp -r client/dist/. /var/www/html/

echo "── Configuring Nginx ────────────────────────────────────────"
cat > /etc/nginx/sites-available/money-app << NGINX
server {
    listen ${APP_PORT} default_server;
    root /var/www/html;
    index index.html;

    # Required for sql.js WASM — wrong MIME type breaks the app
    location ~* \\.wasm\$ {
        add_header Content-Type application/wasm;
        expires 30d;
    }
    location ~* \\.(js|css|ico|png|svg|woff2?)\$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
NGINX

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/money-app /etc/nginx/sites-enabled/money-app
nginx -t
systemctl enable nginx
systemctl restart nginx

echo ""
echo "✓ Done. Container IP: $(hostname -I | awk '{print $1}')"
