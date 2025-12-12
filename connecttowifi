#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# 1. ROOT CHECK
if [ "$(id -u)" -ne 0 ]; then
  echo ">>> Error: Must run as root."
  exit 1
fi

echo ">>> Starting Final System Setup..."

# 1.5 CONNECT TO WI-FI (System-Wide Mode)
echo ">>> Connecting to Wi-Fi ($WIFI_SSID)..."
nmcli radio wifi on

# Delete existing connection if it exists to avoid duplicates
nmcli connection delete "$WIFI_SSID" > /dev/null 2>&1 || true
nmcli device wifi rescan || true
sleep 3

# Connect explicitly naming the connection "$WIFI_SSID"
if nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PASS" name "$WIFI_SSID"; then
    echo ">>> Wi-Fi Connected. Applying system-wide permissions..."
    # 1. Set permissions to empty (Shared with all users)
    nmcli connection modify "$WIFI_SSID" connection.permissions ""
    # 2. Store password in system config (not keyring)
    nmcli connection modify "$WIFI_SSID" wifi-sec.psk-flags 0
    # 3. Ensure autoconnect
    nmcli connection modify "$WIFI_SSID" connection.autoconnect yes
else
    echo ">>> ERROR: Wi-Fi connection failed. The permission fix was skipped."
fi
