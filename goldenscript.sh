#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# --- CONFIGURATION ---
STUDENT_USER="student@SEC.local"
ADMIN_USER_1="secsuperuser"
ADMIN_USER_2="egallen@SEC.local"
INACTIVE_DAYS=120
# ---------------------

# 1. ROOT CHECK
if [ "$(id -u)" -ne 0 ]; then
  echo ">>> Error: Must run as root."
  exit 1
fi

echo ">>> Starting Final System Setup..."

# 2. UPDATES & PACKAGE MANAGEMENT
echo ">>> Updating system..."
sudo apt update && apt upgrade -y
sudo apt autoremove -y

echo ">>> Cleaning packages..."
# Aggressively remove 'deb' versions to prevent duplicates
sudo apt purge "thonny*" "python3-thonny*" "code*" "gnome-initial-setup" "gnome-tour" -y || true

# Delete leftover shortcuts to avoid "Ghost Icons"
sudo rm -f /usr/share/applications/thonny.desktop
sudo rm -f /usr/share/applications/org.thonny.Thonny.desktop
sudo rm -f /usr/share/applications/code.desktop
sudo rm -f /usr/share/applications/vscode.desktop

echo ">>> Installing Snaps..."
# '|| true' ensures script continues if already installed
sudo snap install --classic code || true
sudo snap install thonny || true

# 3. UNIVERSAL CLEANUP LOGIC (Used by Boot & Logout)
cat << EOF > /usr/local/bin/universal_cleanup.sh
#!/bin/bash
TARGET_USER="\$1"
ACTION="\$2" # 'chrome' or 'wipe'

clean_chrome() {
    CHROME_DIR="/home/\$TARGET_USER/.config/google-chrome"
    if [ -d "\$CHROME_DIR" ]; then
        rm -f "\$CHROME_DIR/SingletonLock"
        rm -f "\$CHROME_DIR/SingletonSocket"
        rm -f "\$CHROME_DIR/SingletonCookie"
        logger "CLEANUP: Removed Chrome locks for \$TARGET_USER"
    fi
}

wipe_user() {
    if [ -d "/home/\$TARGET_USER" ]; then
        pkill -u "\$TARGET_USER" || true
        sleep 1
        rm -rf "/home/\$TARGET_USER"
        logger "CLEANUP: Wiped home directory for \$TARGET_USER"
    fi
}

if [ "\$ACTION" == "chrome" ]; then clean_chrome; fi
if [ "\$ACTION" == "wipe" ]; then wipe_user; fi
EOF
chmod +x /usr/local/bin/universal_cleanup.sh

# 4. PAM LOGOUT TRIGGER (Wipes immediately on sign out)
cat << EOF > /usr/local/bin/pam_logout.sh
#!/bin/bash
if [ -z "\$PAM_USER" ]; then exit 0; fi
/usr/local/bin/universal_cleanup.sh "\$PAM_USER" chrome
if [ "\$PAM_USER" == "$STUDENT_USER" ]; then
    /usr/local/bin/universal_cleanup.sh "\$PAM_USER" wipe
fi
EOF
chmod +x /usr/local/bin/pam_logout.sh

if ! grep -q "pam_logout.sh" /etc/pam.d/common-session; then
    echo "session optional pam_exec.so type=close_session /usr/local/bin/pam_logout.sh" >> /etc/pam.d/common-session
fi

# 5. SYSTEMD BOOT CLEANUP (Safety net for crashes + Epoptes Fix)
cat << EOF > /etc/systemd/system/cleanup-boot.service
[Unit]
Description=Safety Cleanup (Chrome, Student, Epoptes)
After=network.target

[Service]
Type=oneshot
User=root
# Wipe student if exists
ExecStart=/bin/bash -c 'if [ -d "/home/$STUDENT_USER" ]; then rm -rf "/home/$STUDENT_USER"; fi'
# Clean Chrome locks globally
ExecStart=/bin/bash -c 'find /home -maxdepth 2 -name "SingletonLock" -delete'
# Clean Stale Epoptes PID (Fixes "Service already running" error)
ExecStart=/bin/bash -c 'rm -f /var/run/epoptes-client.pid'
ExecStartPost=/usr/bin/logger "Systemd: Boot cleanup complete"

[Install]
WantedBy=multi-user.target
EOF
chmod 644 /etc/systemd/system/cleanup-boot.service
systemctl daemon-reload
systemctl enable --now cleanup-boot.service

# 6. UI ENFORCEMENT (The "Brute Force" Script)
echo ">>> generating UI Enforcer script..."

# Detect Snap Filenames dynamically
if [ -f "/var/lib/snapd/desktop/applications/code_code.desktop" ]; then CODE="code_code.desktop"; else CODE="code.desktop"; fi
if [ -f "/var/lib/snapd/desktop/applications/thonny_thonny.desktop" ]; then THONNY="thonny_thonny.desktop"; else THONNY="thonny.desktop"; fi

cat << EOF > /usr/local/bin/force_ui.sh
#!/bin/bash

# --- 1. ADMIN PROTECTION ---
if [ "\$USER" == "$ADMIN_USER_1" ] || [ "\$USER" == "$ADMIN_USER_2" ]; then
    exit 0
fi

# --- 2. WAIT FOR DESKTOP ---
sleep 3

# --- 3. AUDIO (MUTE ON LOGIN) ---
pactl set-sink-mute @DEFAULT_SINK@ 1 > /dev/null 2>&1 || true

# --- 4. VISUALS (FIXED PURPLE ACCENT) ---
# On Ubuntu, "Accent Color" is actually a specific Theme Name.
# We must set both the Interface (Windows) and Icons to 'Yaru-purple'.

gsettings set org.gnome.desktop.interface gtk-theme 'Yaru-purple'
gsettings set org.gnome.desktop.interface icon-theme 'Yaru-purple'
gsettings set org.gnome.desktop.interface color-scheme 'default'

# Hot Corner (Top-Left) & Active Screen Edges
gsettings set org.gnome.desktop.interface enable-hot-corners true
gsettings set org.gnome.mutter edge-tiling true

# Clock & Battery
gsettings set org.gnome.desktop.interface clock-show-seconds true
gsettings set org.gnome.desktop.interface clock-show-weekday true
gsettings set org.gnome.desktop.interface show-battery-percentage true

# --- 5. POWER & PERFORMANCE ---
powerprofilesctl set performance || true

# NO SLEEP / NO BLANK / NO SUSPEND
gsettings set org.gnome.desktop.screensaver lock-enabled false
gsettings set org.gnome.desktop.screensaver idle-activation-enabled false
gsettings set org.gnome.settings-daemon.plugins.power idle-dim false
gsettings set org.gnome.settings-daemon.plugins.power power-saver-profile-on-low-battery false
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 0
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 0
gsettings set org.gnome.desktop.session idle-delay 0

# --- 6. RESTRICTIONS (PRINTERS) ---
gsettings set org.gnome.desktop.lockdown disable-printing true
gsettings set org.gnome.desktop.lockdown disable-print-setup true

# --- 7. DOCK SETTINGS ---
for schema in "org.gnome.shell.extensions.dash-to-dock" "org.gnome.shell.extensions.ubuntu-dock"; do
    gsettings set \$schema dock-position 'BOTTOM'
    gsettings set \$schema autohide true
    gsettings set \$schema extend-height false
    gsettings set \$schema dash-max-icon-size 54
    gsettings set \$schema dock-fixed false
done

# --- 8. ICONS ---
gsettings set org.gnome.shell favorite-apps "['google-chrome.desktop', 'firefox_firefox.desktop', 'org.gnome.Nautilus.desktop', '$CODE', '$THONNY']"

# --- 9. CLEANUP ---
gsettings set org.gnome.shell welcome-dialog-last-shown-version '999999'
EOF

chmod +x /usr/local/bin/force_ui.sh

# Create Autostart Entry
cat << EOF > /etc/xdg/autostart/force_ui.desktop
[Desktop Entry]
Type=Application
Name=Force Student UI
Exec=/usr/local/bin/force_ui.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

# 7. INACTIVE USER CLEANUP (Maintenance)
cat << EOF > /usr/local/bin/cleanup_old_users.sh
#!/bin/bash
set -euo pipefail
lastlog -b "$INACTIVE_DAYS" | awk 'NR>1 {print \$1}' | while read -r U; do
    [[ -z "\$U" || "\$U" == "root" || "\$U" == "$ADMIN_USER_1" || "\$U" == "$ADMIN_USER_2" ]] && continue
    if [ -d "/home/\$U" ]; then
        pkill -u "\$U" || true
        rm -rf "/home/\$U"
        logger "Inactive Cleanup: Wiped profile for \$U"
    fi
done
EOF
chmod 750 /usr/local/bin/cleanup_old_users.sh

# 8. MISC FIXES
echo ">>> Applying final fixes..."

# Epoptes Keepalive (Fixes Black Screens)
cat << EOF > /etc/sysctl.d/99-lab-keepalive.conf
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 3
EOF
sysctl --system

# Hide VNC & Terminal Icons
APPS=("x11vnc.desktop" "xtigervncviewer.desktop" "debian-xterm.desktop" "debian-uxterm.desktop")
for app in "${APPS[@]}"; do
    FILE="/usr/share/applications/$app"
    [ -f "$FILE" ] && echo "NoDisplay=true" >> "$FILE"
done

# 9. CHROME POLICY (Bypass Popups & Force Google)
echo ">>> Configuring Chrome Enterprise Policies..."

# Create the directory for managed policies
mkdir -p /etc/opt/chrome/policies/managed

# Write the policy file.
# This forces Google as the default and disables the "Welcome" and "First Run" screens.
cat << EOF > /etc/opt/chrome/policies/managed/student_policy.json
{
  "DefaultSearchProviderEnabled": true,
  "DefaultSearchProviderName": "Google",
  "DefaultSearchProviderSearchURL": "https://www.google.com/search?q={searchTerms}",
  "DefaultSearchProviderSuggestURL": "https://www.google.com/complete/search?output=chrome&q={searchTerms}",
  "DefaultSearchProviderIconURL": "https://www.google.com/favicon.ico",
  "ShowFirstRunExperience": false,
  "PromotionalTabsEnabled": false,
  "MetricsReportingEnabled": false,
  "BrowserSignin": 0
}
EOF

# Ensure the file is readable by all users
chmod 644 /etc/opt/chrome/policies/managed/student_policy.json

echo ">>> Chrome Policies applied."

# Microbit Rules
echo 'SUBSYSTEM=="tty", ATTRS{idVendor}=="0d28", ATTRS{idProduct}=="0204", MODE="0666"' > "/etc/udev/rules.d/99-microbit.rules"
udevadm control --reload

# File Associations (VS Code for CSV/TXT)
MIME="/usr/share/applications/mimeapps.list"
if [ -f "$MIME" ]; then
    grep -q "\[Default Applications\]" "$MIME" || echo "[Default Applications]" >> "$MIME"
    sed -i '/text\/csv/d' "$MIME"
    sed -i '/text\/plain/d' "$MIME"
    sed -i '/\[Default Applications\]/a text/csv=code_code.desktop' "$MIME"
    sed -i '/\[Default Applications\]/a text/plain=code_code.desktop' "$MIME"
fi

# Reset Student Profile to force new script
rm -f /home/$STUDENT_USER/.config/dconf/user

echo ">>> Setup Complete! Rebooting is highly recommended."
