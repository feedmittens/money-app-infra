#!/bin/bash
# Runs INSIDE the LXC container on first setup.
# Called by lxc-setup.sh via: pct exec <id> -- env VAR=val bash /tmp/money-init.sh
set -euo pipefail

APP_REPO="${APP_REPO:-https://github.com/feedmittens/money-app.git}"
APP_PORT="${APP_PORT:-8080}"
SSL_MODE="${SSL_MODE:-selfsigned}"   # selfsigned | letsencrypt | none
DOMAIN="${DOMAIN:-}"
CERTBOT_EMAIL="${CERTBOT_EMAIL:-}"

echo "── Installing packages ──────────────────────────────────────"
apt-get update -qq
# build-essential + python3 are required to compile better-sqlite3 (native Node module)
apt-get install -y -qq curl git nginx ca-certificates openssl build-essential python3

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

echo "── Installing dependencies ───────────────────────────────────"
cd /opt/money-app
mkdir -p client/public
npm ci --prefix client --silent
npm ci --prefix server --silent

echo "── Building client ──────────────────────────────────────────"
npm run build --prefix client

mkdir -p /var/www/html
cp -r client/dist/. /var/www/html/

echo "── Starting API server ───────────────────────────────────────"
NODE_BIN=$(which node)
printf '[Unit]\nDescription=Money App API Server\nAfter=network.target\n\n[Service]\nType=simple\nWorkingDirectory=/opt/money-app\nExecStart=%s /opt/money-app/server/server.js\nRestart=on-failure\nRestartSec=5\nEnvironment=PORT=3001\nEnvironment=NODE_ENV=production\n\n[Install]\nWantedBy=multi-user.target\n' "$NODE_BIN" \
  > /etc/systemd/system/money-app-api.service

systemctl daemon-reload
systemctl enable money-app-api
systemctl start money-app-api
echo "   ✓ API service started on port 3001"

echo "── Configuring Nginx ────────────────────────────────────────"

# Shared location blocks used in all nginx configs
nginx_locations() {
cat << 'LOCATIONS'
    location /api/ {
        proxy_pass http://127.0.0.1:3001;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        client_max_body_size 50m;
    }
    location ~* \.wasm$ {
        add_header Content-Type application/wasm;
        expires 30d;
    }
    location ~* \.(js|css|ico|png|svg|woff2?)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    location / {
        try_files $uri $uri/ /index.html;
    }
LOCATIONS
}

if [[ "$SSL_MODE" == "selfsigned" ]]; then
  echo "   Generating self-signed certificate (10-year)..."
  CONTAINER_IP=$(hostname -I | awk '{print $1}')
  CN="${DOMAIN:-$CONTAINER_IP}"
  SAN="IP:$CONTAINER_IP"
  [[ -n "$DOMAIN" ]] && SAN="DNS:$DOMAIN,$SAN"

  mkdir -p /etc/nginx/ssl
  openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/money-app.key \
    -out    /etc/nginx/ssl/money-app.crt \
    -subj   "/CN=$CN" \
    -addext "subjectAltName=$SAN" 2>/dev/null
  chmod 600 /etc/nginx/ssl/money-app.key

  cat > /etc/nginx/sites-available/money-app << NGINX
server {
    listen 443 ssl default_server;
    server_name _;

    ssl_certificate     /etc/nginx/ssl/money-app.crt;
    ssl_certificate_key /etc/nginx/ssl/money-app.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    root /var/www/html;
    index index.html;

$(nginx_locations)
}
server {
    listen 80 default_server;
    return 301 https://\$host\$request_uri;
}
NGINX

elif [[ "$SSL_MODE" == "letsencrypt" ]]; then
  if [[ -z "$DOMAIN" || -z "$CERTBOT_EMAIL" ]]; then
    echo "ERROR: DOMAIN and CERTBOT_EMAIL must both be set for SSL_MODE=letsencrypt."
    exit 1
  fi
  cat > /etc/nginx/sites-available/money-app << NGINX
server {
    listen 80;
    server_name ${DOMAIN};
    root /var/www/html;
    index index.html;

$(nginx_locations)
}
NGINX

else
  # SSL_MODE=none — plain HTTP on APP_PORT
  cat > /etc/nginx/sites-available/money-app << NGINX
server {
    listen ${APP_PORT} default_server;
    root /var/www/html;
    index index.html;

$(nginx_locations)
}
NGINX
fi

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/money-app /etc/nginx/sites-enabled/money-app
nginx -t
systemctl enable nginx
systemctl restart nginx

if [[ "$SSL_MODE" == "letsencrypt" ]]; then
  echo "── Obtaining Let's Encrypt certificate ──────────────────────"
  apt-get install -y -qq certbot python3-certbot-nginx
  certbot --nginx \
    -d "$DOMAIN" \
    --non-interactive \
    --agree-tos \
    -m "$CERTBOT_EMAIL" \
    --redirect
  echo "   ✓ SSL configured. Auto-renewal via certbot systemd timer."
fi

echo ""
if [[ "$SSL_MODE" == "selfsigned" ]]; then
  echo "── Certificate fingerprint (SHA-256) ────────────────────────"
  openssl x509 -fingerprint -sha256 -noout -in /etc/nginx/ssl/money-app.crt \
    | sed 's/sha256 Fingerprint=/   /'
fi

echo ""
echo "✓ Done. Container IP: $(hostname -I | awk '{print $1}')"
