#!/usr/bin/env bash
set -euo pipefail
trap '' HUP

if [[ $EUID -ne 0 ]]; then
    echo "Run with root privileges: sudo $0 [PROFILE_NAME_OR_UUID]"
    exit 1
fi

WIFI_COUNTRY="PL"
TARGET_PROFILE="${1:-}"

echo "=== 1. RFKill and Wi-Fi regulatory domain ($WIFI_COUNTRY) ==="
rfkill unblock wifi || true
if command -v raspi-config >/dev/null 2>&1; then
    raspi-config nonint do_wifi_country "$WIFI_COUNTRY" || true
else
    iw reg set "$WIFI_COUNTRY" || true
fi

echo "=== 2. Global NetworkManager configuration (Wi-Fi devices only) ==="
cat << 'EOF' > /etc/NetworkManager/conf.d/99-rpi-wifi-always-on.conf
[connection-wifi]
match-device = type:wifi
wifi.powersave = 2
wifi.cloned-mac-address = permanent
connection.autoconnect-retries = 0
ipv4.dhcp-timeout = 90

[device]
wifi.scan-rand-mac-address = no
EOF
nmcli general reload

echo "=== 3. Installing Wi-Fi watchdog ==="
cat << 'EOF' > /usr/local/sbin/rpi-wifi-watchdog.sh
#!/usr/bin/env bash
WLAN_IF="wlan0"
FAIL_FILE="/run/rpi-wifi-watchdog.fails"

rfkill unblock wifi >/dev/null 2>&1 || true
iw dev "$WLAN_IF" set power_save off >/dev/null 2>&1 || true

STATE=$(nmcli -t -f DEVICE,STATE device | awk -F: -v dev="$WLAN_IF" '$1==dev {print $2}')

# Connection or DHCP in progress: do not interrupt
if [[ "$STATE" == connecting* ]]; then
    exit 0
fi

OK=0
if [[ "$STATE" == "connected" ]]; then
    GW_IP=$(ip -4 route show dev "$WLAN_IF" | awk '/default/ {print $3}' | head -n 1)
    if [[ -z "$GW_IP" ]]; then
        OK=1
    elif ping -I "$WLAN_IF" -c 2 -W 3 "$GW_IP" >/dev/null 2>&1; then
        OK=1
    else
        # ARP fallback for routers blocking ICMP
        ip -4 neigh flush to "$GW_IP" dev "$WLAN_IF" >/dev/null 2>&1 || true
        ping -I "$WLAN_IF" -c 1 -W 2 "$GW_IP" >/dev/null 2>&1 || true
        if ip -4 neigh show to "$GW_IP" dev "$WLAN_IF" 2>/dev/null | grep -q "lladdr"; then
            OK=1
        fi
    fi
fi

if [[ $OK -eq 1 ]]; then
    echo 0 > "$FAIL_FILE"
    exit 0
fi

FAILS=$(( $(cat "$FAIL_FILE" 2>/dev/null || echo 0) + 1 ))
echo "$FAILS" > "$FAIL_FILE"
logger -t wifi-watchdog "Issue with $WLAN_IF (state: $STATE), attempt $FAILS/3"

if (( FAILS >= 3 )); then
    logger -t wifi-watchdog "3 consecutive failures: resetting Wi-Fi radio"
    nmcli radio wifi off
    sleep 3
    nmcli radio wifi on
    echo 0 > "$FAIL_FILE"
else
    nmcli radio wifi on
    nmcli device wifi rescan ifname "$WLAN_IF" >/dev/null 2>&1 || true
    nmcli --wait 30 device connect "$WLAN_IF" >/dev/null 2>&1 || true
fi
EOF
chmod +x /usr/local/sbin/rpi-wifi-watchdog.sh

cat << 'EOF' > /etc/systemd/system/rpi-wifi-watchdog.service
[Unit]
Description=Raspberry Pi Wi-Fi Auto-Reconnect Watchdog
After=NetworkManager.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/rpi-wifi-watchdog.sh
EOF

cat << 'EOF' > /etc/systemd/system/rpi-wifi-watchdog.timer
[Unit]
Description=Run Wi-Fi watchdog every 2 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=2min
Unit=rpi-wifi-watchdog.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now rpi-wifi-watchdog.timer

echo "=== 4. Configuring Wi-Fi profiles ==="
configure_profile() {
    local prof="$1"
    echo " -> Profile: \"$prof\""
    nmcli connection modify "$prof" \
        connection.autoconnect yes \
        connection.autoconnect-priority 100 \
        connection.autoconnect-retries 0 \
        802-11-wireless.powersave 2 \
        802-11-wireless.cloned-mac-address permanent \
        ipv4.dhcp-timeout 90 \
        ipv4.may-fail no
}

if [[ -n "$TARGET_PROFILE" ]]; then
    configure_profile "$TARGET_PROFILE"
else
    # Type can be reported as "wifi" or "802-11-wireless" depending on NM version
    mapfile -t WIFI_UUIDS < <(nmcli -t -f UUID,TYPE connection show | awk -F: '$2=="wifi" || $2=="802-11-wireless" {print $1}')
    if [[ ${#WIFI_UUIDS[@]} -eq 0 ]]; then
        echo "No saved Wi-Fi profile found."
        exit 1
    fi
    for uuid in "${WIFI_UUIDS[@]}"; do
        configure_profile "$uuid"
    done
fi

echo ""
echo "=== Installation complete ==="
echo "Reloading active Wi-Fi in background in 2s (SSH over Wi-Fi may briefly disconnect)."

ACTIVE_WIFI_UUID=$(nmcli -t -f UUID,TYPE connection show --active | awk -F: '$2=="wifi" || $2=="802-11-wireless" {print $1}' | head -n 1 || true)
if [[ -n "$ACTIVE_WIFI_UUID" ]]; then
    nohup bash -c "sleep 2 && nmcli connection up '$ACTIVE_WIFI_UUID'" >/dev/null 2>&1 &
fi
