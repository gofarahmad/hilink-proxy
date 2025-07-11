#!/bin/bash
# HiLink Proxy Auto-Deploy Script
# Full otomatis: colok modem → langsung bisa pakai

# --- Konfigurasi ---
PROXY_USER="proxyuser"
PROXY_PASS=$(openssl rand -hex 8)  # Random password
WEB_PORT=80
DASHBOARD_URL="/etc/hilink-proxy/dashboard-url.txt"

# --- Warna Output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- Fungsi Error ---
error_exit() {
  echo -e "${RED}[ERROR] $1${NC}" >&2
  exit 1
}

# --- Cek Root ---
[ "$(id -u)" -ne 0 ] && error_exit "Script harus dijalankan sebagai root!"

# ==========================================
# 1. INSTALL DEPENDENSI
# ==========================================
echo -e "${YELLOW}[1/5] Menginstall dependencies...${NC}"
apt-get update -q || error_exit "Gagal update package list"
apt-get install -y -q \
  git build-essential \
  python3-pip python3-venv \
  nginx jq curl \
  iptables-persistent || error_exit "Gagal install dependencies"

# ==========================================
# 2. BUILD & INSTALL 3PROXY
# ==========================================
echo -e "${YELLOW}[2/5] Install 3proxy dari source...${NC}"
cd /tmp
git clone https://github.com/z3apa3a/3proxy || error_exit "Gagal clone 3proxy"
cd 3proxy
make -f Makefile.Linux || error_exit "Build 3proxy gagal"
make install || error_exit "Install 3proxy gagal"

# Buat user proxy
useradd -r -s /bin/false $PROXY_USER
echo "$PROXY_USER:$PROXY_PASS" > /etc/3proxy/.3proxy_passwd

# ==========================================
# 3. SETUP AUTOCONFIG SYSTEM
# ==========================================
echo -e "${YELLOW}[3/5] Setup auto-config...${NC}"

# Clone repo config
mkdir -p /etc/hilink-proxy
git clone https://github.com/username/hilink-proxy-server.git /etc/hilink-proxy/repo || error_exit "Gagal clone repo config"

# Install udev rule
cp /etc/hilink-proxy/repo/auto-config/udev/99-hilink.rules /etc/udev/rules.d/
udevadm control --reload-rules

# Install systemd services
cp /etc/hilink-proxy/repo/auto-config/systemd/*.service /etc/systemd/system/
systemctl daemon-reload

# Install scripts
cp /etc/hilink-proxy/repo/auto-config/scripts/*.sh /usr/local/bin/
chmod +x /usr/local/bin/{hilink-autoconf,update-3proxy}.sh

# ==========================================
# 4. SETUP NGINX DASHBOARD
# ==========================================
echo -e "${YELLOW}[4/5] Setup dashboard...${NC}"

# Buat config Nginx
cat > /etc/nginx/sites-available/hilink-proxy <<EOF
server {
    listen $WEB_PORT;
    root /etc/hilink-proxy/repo/dashboard;
    
    location / {
        try_files \$uri \$uri/ /index.html;
    }
    
    location /api {
        proxy_pass http://127.0.0.1:5000;
    }
    
    location /proxy-info {
        alias /etc/hilink-proxy/;
        autoindex on;
    }
}
EOF

ln -s /etc/nginx/sites-available/hilink-proxy /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# ==========================================
# 5. START SERVICES & FINAL CONFIG
# ==========================================
echo -e "${YELLOW}[5/5] Starting services...${NC}"

# Enable services
systemctl enable hilink-autoconf 3proxy nginx
systemctl start hilink-autoconf 3proxy nginx || error_exit "Gagal start services"

# Firewall
ufw allow $WEB_PORT/tcp
ufw allow 7001:8999/tcp
ufw --force enable

# Simpan info akses
IP=$(hostname -I | awk '{print $1}')
echo -e "${GREEN}\n=== INSTALASI SELESAI ==="
echo -e "Dashboard URL: http://$IP"
echo -e "Proxy Ports: 7001-8999 (auto-assign per modem)"
echo -e "Credentials: $PROXY_USER / $PROXY_PASS"
echo -e "Config Dir: /etc/hilink-proxy/${NC}"

# Simpan URL untuk akses nanti
echo "http://$IP" > $DASHBOARD_URL