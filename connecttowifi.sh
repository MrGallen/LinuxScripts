#!/bin/bash
set -e  # Exit on error

# WI-FI SETTINGS
WIFI_SSID="Admin"
WIFI_PASS="bhd56x9064bdaz697fyc21ggh"

# 1. ROOT CHECK
if [ "$(id -u)" -ne 0 ]; then
  echo ">>> Error: Must run as root."
  exit 1
fi

echo ">>> Starting Final System Setup..."

# 1.5 CONNECT TO WI-FI (System-Wide Mode)
echo ">>> Connecting to Wi-Fi ($WIFI_SSID)..."
nmcli radio wifi on

# Delete existing connection to avoid duplicates
# usage of '|| true' ensures script doesn't exit if connection doesn't exist
nmcli connection delete "$WIFI_SSID" > /dev/null 2>&1 || true

# Rescan to ensure SSID is visible
nmcli device wifi rescan || true
sleep 5 # Increased slightly to ensure scan completes

# Connect
# We use 'name' to ensure the connection profile matches our variable
if nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PASS" name "$WIFI_SSID"; then
    echo ">>> Wi-Fi Connected. Applying system-wide permissions..."

    # 1. Set permissions to empty (Shared with all users)
    nmcli connection modify "$WIFI_SSID" connection.permissions ""
    
    # 2. Store password in system config (plain text in root-owned file, not keyring)
    nmcli connection modify "$WIFI_SSID" wifi-sec.psk-flags 0
    
    # 3. Ensure autoconnect
    nmcli connection modify "$WIFI_SSID" connection.autoconnect yes

    # 4. RESTART CONNECTION (Recommended)
    # This ensures the new 'system-wide' flags are actually loaded by the daemon
    echo ">>> Reloading connection profile..."
    nmcli connection up "$WIFI_SSID"
else
    echo ">>> ERROR: Wi-Fi connection failed."
    exit 1
fi

# D. SELF DESTRUCT
echo ">>> CONFIGURATION COMPLETE."
echo ">>> Deleting this script file to protect Wi-Fi passwords..."
rm -- "$0"
echo ">>> Script deleted. Please Reboot."
