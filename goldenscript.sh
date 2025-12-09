#!/bin/bash
set -e  # Stop on error

# --- CONFIGURATION ---
STUDENT_USER="student@SEC.local"  # Exact username to wipe
ADMIN_USER="secsuperuser"         # User to protect
INACTIVE_DAYS=120
# ---------------------

# 1. Root Check
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be running as root. Exiting."
  exit 1
fi

echo ">>> Starting System Setup..."

# 2. Updates & Package Management
echo ">>> Updating system..."
sudo apt update && apt upgrade -y
sudo apt autoremove -y

echo ">>> Managing packages..."
# Purge conflicting DEBs
sudo apt purge code thonny zenity gnome-initial-setup -y || true

# Install Snaps
sudo snap install --classic code || true
sudo snap install thonny

# 3. Create The "Wipe & Clean" Logic

# --- Script A: The Universal Cleaner (Used by Boot AND Logout) ---
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
        # Kill user processes first to allow clean deletion
        pkill -u "\$TARGET_USER" || true
        sleep 1
        rm -rf "/home/\$TARGET_USER"
        logger "CLEANUP: Wiped home directory for \$TARGET_USER"
    fi
}

if [ "\$ACTION" == "chrome" ]; then
    clean_chrome
elif [ "\$ACTION" == "wipe" ]; then
    wipe_user
fi
EOF
chmod +x /usr/local/bin/universal_cleanup.sh

# --- Script B: PAM Logout Trigger ---
cat << EOF > /usr/local/bin/pam_logout.sh
#!/bin/bash
# This script runs whenever ANY user logs out.

if [ -z "\$PAM_USER" ]; then exit 0; fi

# 1. Clean Chrome locks for EVERYONE on logout
/usr/local/bin/universal_cleanup.sh "\$PAM_USER" chrome

# 2. Wipe Student Account completely on logout
if [ "\$PAM_USER" == "$STUDENT_USER" ]; then
    /usr/local/bin/universal_cleanup.sh "\$PAM_USER" wipe
fi
EOF
chmod +x /usr/local/bin/pam_logout.sh

# Register PAM module
if ! grep -q "pam_logout.sh" /etc/pam.d/common-session; then
    echo "session optional pam_exec.so type=close_session /usr/local/bin/pam_logout.sh" >> /etc/pam.d/common-session
fi

# 4. Configure Crontab (Shutdown & Updates)
cat << EOF > /etc/crontab
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# m h dom mon dow user  command
@reboot root apt update && apt upgrade -y && apt autoremove -y
15 16 * * * root shutdown -h now
02 16 * * * root apt update && apt upgrade -y && apt autoremove -y
EOF

# 5. Systemd: Boot Cleanup (Safety Net)
cat << EOF > /etc/systemd/system/cleanup-boot.service
[Unit]
Description=Safety Cleanup on Boot (Chrome Locks + Student Wipe + Epoptes)
After=network.target

[Service]
Type=oneshot
User=root
# Wipe student folder if it exists
ExecStart=/bin/bash -c 'if [ -d "/home/$STUDENT_USER" ]; then rm -rf "/home/$STUDENT_USER"; fi'
# Clean Chrome locks for ALL users
ExecStart=/bin/bash -c 'find /home -maxdepth 2 -name "SingletonLock" -delete'
# Clean stale Epoptes Client PID
ExecStart=/bin/bash -c 'rm -f /var/run/epoptes-client.pid'

ExecStartPost=/usr/bin/logger "Systemd: Boot cleanup complete"

[Install]
WantedBy=multi-user.target
EOF
chmod 644 /etc/systemd/system/cleanup-boot.service

# 6. Systemd: Inactive User Cleanup
cat << EOF > /usr/local/bin/cleanup_old_users.sh
#!/bin/bash
set -euo pipefail

DAYS=$INACTIVE_DAYS
DOMAIN_SUFFIX="@SEC.local"
SKIP_USER="$ADMIN_USER"
LOG_FILE="/var/log/cleanup_old_users.log"

lastlog -b "\$DAYS" | awk -v suf="\$DOMAIN_SUFFIX" 'NR>1 && index(\$0, suf){print \$1}' | while read -r USER_ACCOUNT; do
    [[ -z "\$USER_ACCOUNT" ]] && continue
    [[ "\$USER_ACCOUNT" == "root" ]] && continue
    [[ "\$USER_ACCOUNT" == "\$SKIP_USER" ]] && continue

    HOME_DIR="/home/\$USER_ACCOUNT"
    if [ -d "\$HOME_DIR" ]; then
        pkill -u "\$USER_ACCOUNT" || true
        rm -rf "\$HOME_DIR"
        echo "\$(date) INFO: Removed \$HOME_DIR for \$USER_ACCOUNT" >> "\$LOG_FILE"
        logger "Inactive Cleanup: Wiped profile for \$USER_ACCOUNT"
    fi
done
EOF
chmod 750 /usr/local/bin/cleanup_old_users.sh

cat << EOF > /etc/systemd/system/delete-inactive-users.service
[Unit]
Description=Cleanup Inactive Profiles
After=network-online.target sssd.service

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/bin/cleanup_old_users.sh
EOF

cat << EOF > /etc/systemd/system/delete-inactive-users.timer
[Unit]
Description=Run Inactive User Cleanup Monthly
[Timer]
OnCalendar=Wed *-*-1..7 13:20:00
Persistent=true
RandomizedDelaySec=5m
[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now cleanup-boot.service
systemctl enable --now delete-inactive-users.timer

# 7. UI Customization (GNOME dconf)
apt purge gnome-initial-setup gnome-tour -y || true
echo ">>> Applying GNOME settings..."
mkdir -p /etc/dconf/profile
echo "user-db:user" > /etc/dconf/profile/user
echo "system-db:custom" >> /etc/dconf/profile/user
mkdir -p /etc/dconf/db/custom.d/locks

# Settings
cat << EOF > /etc/dconf/db/custom.d/00-config
[org/gnome/settings-daemon/plugins/power]
ambient-enabled=false
idle-brightness=30
idle-dim=false
lid-close-ac-action="suspend"
lid-close-battery-action="suspend"
power-button-action="interactive"
sleep-inactive-ac-timeout=0
sleep-inactive-battery-timeout=0

[org/gnome/desktop/screensaver]
idle-activation-enabled=false
lock-enabled=false

[org/gnome/desktop/session]
idle-delay=uint32 0

[org/gnome/desktop/interface]
accent-color="purple"
color-scheme="prefer-light"
clock-show-seconds=true
clock-show-weekday=true
show-battery-percentage=true

[org/gnome/shell/extensions/dash-to-dock]
autohide=true
dock-fixed=false
extend-height=true
dash-max-icon-size=54
dock-position="BOTTOM"

[org/gnome/shell]
favorite-apps=['google-chrome.desktop', 'firefox_firefox.desktop', 'libreoffice-writer.desktop', 'libreoffice-calc.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Terminal.desktop', 'code_code.desktop', 'thonny_thonny.desktop']
EOF

# Locks
cat << EOF > /etc/dconf/db/custom.d/locks/00-lock
/org/gnome/settings-daemon/plugins/power/ambient-enabled
/org/gnome/settings-daemon/plugins/power/idle-brightness
/org/gnome/settings-daemon/plugins/power/idle-dim
/org/gnome/settings-daemon/plugins/power/lid-close-ac-action
/org/gnome/desktop/screensaver/idle-activation-enabled
/org/gnome/desktop/screensaver/lock-enabled
/org/gnome/desktop/session/idle-delay
/org/gnome/desktop/interface/show-battery-percentage
/org/gnome/shell/extensions/dash-to-dock/dock-position
/org/gnome/shell/extensions/dash-to-dock/autohide
/org/gnome/shell/favorite-apps
EOF
dconf update

# 8. Miscellaneous
echo ">>> Performing final cleanup..."

# Epoptes Keepalive Fix
cat << EOF > /etc/sysctl.d/99-lab-keepalive.conf
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 3
EOF
sysctl --system

# Hide VNC/Terminals
APPS=("x11vnc.desktop" "xtigervncviewer.desktop" "debian-xterm.desktop" "debian-uxterm.desktop")
for app in "${APPS[@]}"; do
    FILE="/usr/share/applications/$app"
    [ -f "$FILE" ] && echo "NoDisplay=true" >> "$FILE"
done

# Microbit Rules
echo 'SUBSYSTEM=="tty", ATTRS{idVendor}=="0d28", ATTRS{idProduct}=="0204", MODE="0666"' > "/etc/udev/rules.d/99-microbit.rules"
udevadm control --reload

# 9. File Associations
MIME_LIST="/usr/share/applications/mimeapps.list"
if [ -f "$MIME_LIST" ]; then
    grep -q "\[Default Applications\]" "$MIME_LIST" || echo "[Default Applications]" >> "$MIME_LIST"
    sed -i '/text\/csv/d' "$MIME_LIST"
    sed -i '/text\/plain/d' "$MIME_LIST"
    sed -i '/\[Default Applications\]/a text/csv=code_code.desktop' "$MIME_LIST"
    sed -i '/\[Default Applications\]/a text/plain=code_code.desktop' "$MIME_LIST"
fi

echo ">>> Setup Complete! Please Reboot."
