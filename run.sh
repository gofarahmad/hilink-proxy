#!/bin/bash
# Full Auto-Deploy Script for HiLink Proxy Server
# Termasuk ModemManager, curl, dan penempatan file otomatis

# --- Konfigurasi ---
APP_NAME="hilink-proxy"
APP_DIR="/opt/$APP_NAME"
WEB_ROOT="/var/www/$APP_NAME"
APP_PORT=5000
NGINX_CONF="/etc/nginx/sites-available/$APP_NAME"
MODEM_CONFIG="/etc/$APP_NAME/modems.json"
LOG_FILE="/var/log/${APP_NAME}-install.log"

# --- Warna Output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- Fungsi ---
error_exit() {
  echo -e "${RED}[ERROR] $1${NC}" | tee -a $LOG_FILE
  exit 1
}

log() {
  echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a $LOG_FILE
}

success() {
  echo -e "${GREEN}$1${NC}" | tee -a $LOG_FILE
}

# --- Cek Root ---
[ "$(id -u)" -ne 0 ] && error_exit "Script harus dijalankan sebagai root!"

# ==========================================
# 1. INSTALL SEMUA DEPENDENSI SISTEM
# ==========================================
log "[1/6] Menginstall system dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -q | tee -a $LOG_FILE || error_exit "Gagal update package list"

# Daftar semua dependencies yang diperlukan
DEPS=(
  git build-essential
  python3 python3-pip python3-venv
  nginx
  modemmanager
  curl
  jq
  usb-modeswitch
  net-tools
  vnstat
  iptables-persistent
)

for pkg in "${DEPS[@]}"; do
  if ! dpkg -l | grep -q "^ii  $pkg "; then
    apt-get install -y -q "$pkg" | tee -a $LOG_FILE || error_exit "Gagal install $pkg"
    log "✓ Package $pkg terinstall"
  else
    log "✓ Package $pkg sudah ada"
  fi
done

# ==========================================
# 2. SETUP REPOSITORY & STRUKTUR DIREKTORI
# ==========================================
log "[2/6] Setup struktur direktori..."

# Clone repo ke /root jika belum ada
if [ ! -d "/root/$APP_NAME" ]; then
  git clone https://github.com/gofarahmad/ProxyPilot /root/$APP_NAME | tee -a $LOG_FILE || error_exit "Gagal clone repository"
fi

# Buat struktur direktori
mkdir -p \
  $APP_DIR \
  $WEB_ROOT \
  /etc/$APP_NAME \
  /usr/local/3proxy/{conf,logs} \
  /var/log/$APP_NAME

# ==========================================
# 3. INSTALL & KONFIGURASI 3PROXY
# ==========================================
log "[3/6] Install 3proxy..."

if [ ! -f "/usr/local/3proxy/bin/3proxy" ]; then
  cd /tmp
  git clone https://github.com/z3apa3a/3proxy | tee -a $LOG_FILE || error_exit "Gagal clone 3proxy"
  cd 3proxy
  make -f Makefile.Linux | tee -a $LOG_FILE || error_exit "Build 3proxy gagal"
  make install | tee -a $LOG_FILE || error_exit "Install 3proxy gagal"
else
  log "✓ 3proxy sudah terinstall"
fi

# Buat config dasar 3proxy
cat > /usr/local/3proxy/conf/3proxy.cfg <<EOF
daemon
nserver 8.8.8.8
nserver 1.1.1.1
log /var/log/3proxy.log D
logformat "- +_L%t.%. %N.%p %E %U %C:%c %R:%r %O %I %h %T"
users \$/etc/3proxy/.3proxy_passwd
allow * * * 25,80,443,7001-8999
auth strong
maxconn 100
flush
EOF

# ==========================================
# 4. SETUP BACKEND & FRONTEND
# ==========================================
log "[4/6] Deploy aplikasi..."

# Copy file dari repo /root ke lokasi target
cp -r /root/$APP_NAME/backend $APP_DIR/
cp -r /root/$APP_NAME/frontend/dist/* $WEB_ROOT/
cp /root/$APP_NAME/auto-config/* /usr/local/bin/

# Setup Python virtualenv
cd $APP_DIR/backend
if [ ! -d "venv" ]; then
  python3 -m venv venv | tee -a $LOG_FILE || error_exit "Gagal buat virtualenv"
fi
source venv/bin/activate
pip install -r requirements.txt | tee -a $LOG_FILE || error_exit "Gagal install Python dependencies"

# Buat config modem jika belum ada
if [ ! -f "$MODEM_CONFIG" ]; then
  cat > $MODEM_CONFIG <<EOF
{
  "modems": []
}
EOF
fi

# ==========================================
# 5. KONFIGURASI SERVICE & NGINX
# ==========================================
log "[5/6] Konfigurasi services..."

# Systemd service untuk backend
cat > /etc/systemd/system/$APP_NAME.service <<EOF
[Unit]
Description=HiLink Proxy Backend Service
After=network.target ModemManager.service

[Service]
User=www-data
WorkingDirectory=$APP_DIR/backend
Environment="PATH=$APP_DIR/backend/venv/bin"
ExecStart=$APP_DIR/backend/venv/bin/gunicorn -w 4 -b 127.0.0.1:$APP_PORT app:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Systemd service untuk 3proxy
cat > /etc/systemd/system/3proxy.service <<EOF
[Unit]
Description=3Proxy Service
After=network.target $APP_NAME.service

[Service]
Type=simple
ExecStart=/usr/local/3proxy/bin/3proxy /usr/local/3proxy/conf/3proxy.cfg
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Konfigurasi Nginx
cat > $NGINX_CONF <<EOF
server {
    listen 80;
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
    }

    location /proxy-info {
        alias /etc/$APP_NAME/;
        autoindex on;
    }
}
EOF

ln -sf $NGINX_CONF /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# ==========================================
# 6. AKTIFKAN SERVICE & FINAL CONFIG
# ==========================================
log "[6/6] Starting services..."

systemctl daemon-reload
systemctl enable ModemManager $APP_NAME 3proxy nginx | tee -a $LOG_FILE
systemctl restart ModemManager $APP_NAME 3proxy nginx | tee -a $LOG_FILE || error_exit "Gagal start services"

# Firewall rules
ufw allow 80/tcp | tee -a $LOG_FILE
ufw allow 22/tcp | tee -a $LOG_FILE
ufw allow 7001:8999/tcp | tee -a $LOG_FILE
ufw --force enable | tee -a $LOG_FILE

# ==========================================
# SELESAI
# ==========================================
PUBLIC_IP=$(curl -s ifconfig.me)
success "\n=== INSTALASI BERHASIL ==="
success "Dashboard: http://$PUBLIC_IP"
success "Modem Management:"
success "  - ModemManager aktif"
success "  - Contoh perintah: mmcli -L"
success "Proxy Ports: 7001-8999 (auto-assign)"
success "File Konfigurasi:"
success "  - Modem: $MODEM_CONFIG"
success "  - 3proxy: /usr/local/3proxy/conf/3proxy.cfg"
success "  - Nginx: $NGINX_CONF"
success "Log Instalasi: $LOG_FILE"