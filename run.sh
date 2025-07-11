#!/bin/bash
# Enhanced Auto-Deploy Script for NodeProxy

# --- Configuration ---
APP_NAME="nodeproxy"
APP_DIR="/opt/$APP_NAME"
WEB_ROOT="/var/www/$APP_NAME"
APP_PORT=5000
NGINX_PORT=80

# --- Phase 0: Enhanced Pre-flight ---
if [ "$(id -u)" -ne 0 ]; then
  echo "✗ Error: Root required" >&2
  exit 1
fi

for cmd in git nginx python3 node npm; do
  if ! command -v $cmd >/dev/null 2>&1; then
    echo "✗ Missing dependency: $cmd" >&2
    exit 1
  done
done

# --- Phase 1: Optimized Dependency Install ---
echo "✓ [1/7] Installing dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get upgrade -y
apt-get install -y \
  git nginx python3-pip python3-venv \
  nodejs npm net-tools vnstat \
  iptables-persistent netplan.io gunicorn

# --- Phase 2: Directory Setup with Permissions ---
echo "✓ [2/7] Creating directories..."
mkdir -p $WEB_ROOT $APP_DIR /etc/$APP_NAME/{config,logs}
chown -R www-data:www-data /etc/$APP_NAME
chmod 750 /etc/$APP_NAME

# --- Phase 3: Safe Code Deployment ---
echo "✓ [3/7] Deploying application..."
if [ -d "$APP_DIR/.git" ]; then
  cd $APP_DIR
  git stash && git pull
else
  git clone https://github.com/gofarahmad/nodeproxy.git $APP_DIR || exit 1
fi

# --- Phase 4: Robust Backend Setup ---
echo "✓ [4/7] Configuring backend..."
cd $APP_DIR/backend
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip wheel
pip install -r requirements.txt || exit 1

# Secure config
cat > /etc/$APP_NAME/config/production.ini <<EOF
[app]
port = $APP_PORT
debug = false
secret_key = $(openssl rand -hex 32)

[database]
path = /var/lib/$APP_NAME/db.sqlite
EOF

# Systemd with hardening
cat > /etc/systemd/system/$APP_NAME.service <<EOF
[Unit]
Description=NodeProxy Backend
After=network.target

[Service]
User=www-data
Group=www-data
WorkingDirectory=$APP_DIR/backend
Environment="PATH=$APP_DIR/backend/venv/bin"
EnvironmentFile=/etc/$APP_NAME/.env
ExecStart=/usr/bin/gunicorn \
  --workers 4 \
  --bind 127.0.0.1:$APP_PORT \
  --access-logfile /var/log/$APP_NAME-access.log \
  --error-logfile /var/log/$APP_NAME-error.log \
  --capture-output \
  app:app
Restart=always
RestartSec=5
ProtectSystem=full
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

# --- Phase 5: Frontend Build with Validation ---
echo "✓ [5/7] Building frontend..."
cd $APP_DIR/frontend
npm ci --production || exit 1
npm run build || exit 1
cp -r dist/* $WEB_ROOT/

# --- Phase 6: Secure Nginx Configuration ---
echo "✓ [6/7] Configuring Nginx..."
cat > /etc/nginx/sites-available/$APP_NAME <<EOF
server {
    listen $NGINX_PORT;
    server_name _;

    root $WEB_ROOT;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
        add_header X-Frame-Options DENY;
        add_header X-Content-Type-Options nosniff;
    }

    location /api {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico)$ {
        expires 1y;
        add_header Cache-Control "public";
    }
}
EOF

# --- Phase 7: Secure Service Activation ---
echo "✓ [7/7] Starting services..."
systemctl daemon-reload
systemctl enable $APP_NAME
systemctl restart $APP_NAME nginx

# Firewall with rate limiting
ufw allow $NGINX_PORT/tcp
ufw allow 22/tcp
ufw allow 7001:8999/tcp && ufw limit 7001:8999/tcp
ufw --force enable

# --- Post-Deploy Verification ---
echo "Running post-install checks..."
if systemctl is-active --quiet $APP_NAME; then
  echo "✅ Backend service is running"
else
  echo "❌ Backend service failed!" >&2
  journalctl -u $APP_NAME -n 10 --no-pager
fi

PUBLIC_IP=$(curl -4 -s ifconfig.me)
echo "========================================"
echo " Deployment Complete!"
echo " Dashboard: http://$PUBLIC_IP"
echo "========================================"