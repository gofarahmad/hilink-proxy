#!/bin/bash
# Dynamically update 3proxy configuration

CONFIG="/etc/3proxy/3proxy.cfg"
MODEM_CONFIG="/etc/hilink-proxy/modems.json"
TEMP_CONFIG="/tmp/3proxy.cfg.$$"

# Generate new config
{
  echo "daemon"
  echo "nserver 8.8.8.8"
  echo "nserver 1.1.1.1"
  echo "log /var/log/3proxy.log D"
  echo "logformat \"- +_L%t.%. %N.%p %E %U %C:%c %R:%r %O %I %h %T\""
  echo "users /etc/3proxy/.3proxy_passwd"
  echo "auth strong"
  echo "allow * * * 25,80,443,7001-8999"
  echo "maxconn 50"
  echo "flush"

  # Add modem configurations
  if [ -f "$MODEM_CONFIG" ]; then
    jq -r '.modems[] | 
      "proxy -a -p\(.ports.http) -i\(.ip) -e\(.ip | sub("\\.1$"; ".100"))\n" +
      "socks -a -p\(.ports.socks) -i\(.ip) -e\(.ip | sub("\\.1$"; ".100"))\n" +
      "bandwidth \(.id | ltrimstr("modem") | tonumber):1024000"' "$MODEM_CONFIG"
  fi

  echo "rotate 30"
} > "$TEMP_CONFIG"

# Validate and replace config
if /usr/local/3proxy/bin/3proxy -c "$TEMP_CONFIG" -f; then
  mv "$TEMP_CONFIG" "$CONFIG"
  echo "[$(date)] Config updated" >> /var/log/3proxy-update.log
else
  echo "[$(date)] Config validation failed" >> /var/log/3proxy-update.log
  rm -f "$TEMP_CONFIG"
  exit 1
fi