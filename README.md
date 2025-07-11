
# hilink-proxy

Sistem backend proxy berbasis modem HiLink (Huawei E3372h HiLink Mode), dikontrol melalui API Python dan dashboard React, serta otomatisasi dengan systemd service.

---

## 📦 Struktur Folder

```
/etc/hilink-proxy/
├── repo/                         # hasil clone repo GitHub
│   ├── backend/                  # API backend (FastAPI)
│   ├── frontend/                 # React dashboard
│   ├── auto-config/
│   │   ├── systemd/*.service     # service file
│   │   └── scripts/*.sh          # script shell otomatisasi
...
```

---

## 🧩 Instalasi

### 1. Clone repo ke `/etc/hilink-proxy`

```bash
sudo mkdir -p /etc/hilink-proxy
sudo git clone https://github.com/gofarahmad/hilink-proxy /etc/hilink-proxy/repo
```

> Ganti `username` dengan akun GitHub kamu yang berisi repositori ini.

---

### 2. Install systemd service

```bash
sudo cp /etc/hilink-proxy/repo/auto-config/systemd/*.service /etc/systemd/system/
sudo cp /etc/hilink-proxy/repo/auto-config/scripts/*.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/{hilink-autoconf,update-3proxy}.sh
sudo systemctl daemon-reload
```

---

### 3. Aktifkan servicenya

```bash
sudo systemctl enable --now hilink-autoconf 3proxy
```

> Service `hilink-autoconf` bertanggung jawab untuk:
> - Deteksi modem
> - Set IP route dari HiLink
> - Update config 3proxy

---

## 🚀 Jalankan Secara Manual (Opsional)

```bash
sudo /usr/local/bin/hilink-autoconf.sh
sudo systemctl restart 3proxy
```

---

## 📂 Konfigurasi Proxy

Edit file `config/modems.json` untuk menentukan:
- IP lokal HiLink (misal `192.168.8.1`)
- Interface modem (`eth3`, `usb0`)
- Port proxy yang akan digunakan

---

## 🧪 Uji Proxy

```bash
curl --proxy 127.0.0.1:3128 https://api.ipify.org
```

---

## 🔧 Tools

- FastAPI untuk REST API backend
- 3proxy untuk SOCKS5/HTTP proxy
- ReactJS untuk dashboard frontend
- Bash script + systemd untuk automation

---

## 🛠 Untuk Developer

Clone dan jalankan backend API:

```bash
cd backend
pip install -r requirements.txt
uvicorn app:app --reload --host 0.0.0.0 --port 8000
```

Jalankan frontend:

```bash
cd frontend
npm install
npm run dev
```

---

© 2025 by [Gofar]
