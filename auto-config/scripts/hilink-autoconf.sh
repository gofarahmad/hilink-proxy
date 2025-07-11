#!/bin/bash
# Auto-detect and configure HiLink modems

CONFIG=${MODEM_CONFIG:-/etc/hilink-proxy/modems.json}
LOG=${LOG_FILE:-/var/log/hilink-autoconf.log}

# Initialize config if not exists
[ -f "$CONFIG" ] || echo '{"modems":[]}' > "$CONFIG"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"
}

detect_modems() {
  log "Starting modem detection..."
  for i in {11..30}; do
    IP="192.168.${i}.1"
    
    # Skip if already configured
    if jq -e ".modems[] | select(.ip == \"$IP\")" "$CONFIG" >/dev/null; then
      continue
    fi

    # Check modem availability
    if curl -s --connect-timeout 2 "http://$IP/api/device/information" | grep -q "Imei"; then
      IMEI=$(curl -s "http://$IP/api/device/information" | grep -oPm1 "(?<=<Imei>)[^<]+")
      MODEL=$(curl -s "http://$IP/api/device/information" | grep -oPm1 "(?<=<DeviceName>)[^<]+")
      
      # Add new modem
      jq --arg ip "$IP" \
         --arg id "modem$i" \
         --arg imei "$IMEI" \
         --arg model "$MODEL" \
         '.modems += [{
           "id": $id,
           "ip": $ip,
           "imei": $imei,
           "model": $model,
           "apn": "internet",
           "ports": {
             "http": $i | tonumber + 8000,
             "socks": $i | tonumber + 8100
           },
           "created_at": now|todate
         }]' "$CONFIG" > tmp.$$.json && mv tmp.$$.json "$CONFIG"
      
      log "Detected new modem: $MODEL (IMEI: $IMEI) at $IP"
    fi
  done
}

# Main loop
while true; do
  detect_modems
  sleep 30
done