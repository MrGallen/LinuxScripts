#!/bin/bash
set -e  # Stop the script immediately if any command fails

# 1. Root Check
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be running as root. Exiting."
  exit 1
fi

echo ">>> Starting System Setup..."

# 2. Updates & Package Management
echo ">>> Updating system..."
sudo apt update && apt upgrade -y

echo ">>> Managing packages..."
# Remove deb versions
sudo apt purge code || true
sudo apt purge thonny || true
sudo apt purge zenity || true
sudo apt purge gnome-initial-setup || true
sudo apt autoremove -y

# Install snap versions
sudo snap install --classic code
sudo snap install thonny

# 3. Create Maintenance Scripts using Heredocs

# --- Script A: Clear Accounts (Manual Audit Tool) ---
mkdir -p /home/secsuperuser/scripts
cat << 'EOF' > /home/secsuperuser/scripts/clearaccounts.sh
#!/bin/bash
set -euo pipefail

LOG_FILE="/var/log/clearaccounts.log"
mkdir -p "$(dirname "$LOG_FILE")"

DAYS_LIMIT=120
SECONDS_LIMIT=$(( DAYS_LIMIT * 86400 ))
epoch_now=$(date +%s)

for dir in /home/*; do
  [[ -d "$dir" ]] || continue
  user="${dir##*/}"
  
  # Exclusions
  [[ "$user" == "*" ]] && continue
  [[ "$user" == "secsuperuser" ]] && continue
  [[ "$user" == "egallen@SEC.local" ]] && continue

  line=$(last -F -- "$user" 2>/dev/null | grep "login screen" | head -n1 || true)
  
  if [[ -z "$line" ]]; then
    echo "$(date) ERROR: no login screen record found for $user" >> "$LOG_FILE"
    continue
  fi

  # Extract date using awk
  collapsed=$(echo "$line" | tr -s " ")
  date_str=$(echo "$collapsed" | awk '{ for(i=5;i<=9;i++) printf "%s%s", $i, (i<9?" ":""); }')

  if ! epoch_last=$(date -d "$date_str" +%s 2>/dev/null); then
    echo "$(date) ERROR: failed to parse date $date_str for $user" >> "$LOG_FILE"
    continue
  fi

  seconds_passed=$(( epoch_now - epoch_last ))

  if (( seconds_passed > SECONDS_LIMIT )); then
    rm -fr "$dir"
    echo "$(date) INFO: $user home directory cleared (Inactive > $DAYS_LIMIT days)" >> "$LOG_FILE"
  fi
done
EOF
chmod +x /home/secsuperuser/scripts/clearaccounts.sh

# --- Script B: Logout Cleanup (Chrome Locks + Student Wipe) ---
cat << 'EOF' > /usr/local/bin/logout_cleanup.sh
#!/bin/bash

# 1. GLOBAL FIX: Remove Chrome Locks for ALL users
# This prevents "Profile in use" errors
CHROME_DIR="/home/$PAM_USER/.config/google-chrome"
if [ -d "$CHROME_DIR" ]; then
    rm -f "$CHROME_DIR/SingletonLock"
    rm -f "$CHROME_DIR/SingletonSocket"
    rm -f "$CHROME_DIR/SingletonCookie"
    logger "PAM_EXEC: Cleared Chrome locks for $PAM_USER"
fi

EOF
chmod +x /usr/local/bin/logout_cleanup.sh

# Safely add to PAM
if ! grep -q "logout_cleanup.sh" /etc/pam.d/common-session; then
    echo "session optional pam_exec.so type=close_session /usr/local/bin/logout_cleanup.sh" >> /etc/pam.d/common-session
    echo ">>> PAM module added."
else
    echo ">>> PAM module already exists. Skipping."
fi

# 4. Configure Crontab
cat << 'EOF' > /etc/crontab
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# m h dom mon dow user  command
@reboot root apt update && apt upgrade -y && apt autoremove -y
15 16 * * * root shutdown -h now
02 16 * * * root apt update && apt upgrade -y && apt autoremove -y
EOF

# 5. Systemd: Wipe Student on Boot
cat << 'EOF' > /etc/systemd/system/cleanup-student.service
[Unit]
Description=Wipe Student AD Profile on Boot
After=network-online.target sssd.service systemd-user-sessions.service
Wants=network-online.target

[Service]
Type=oneshot
User=root
ExecStart=/bin/bash -c 'if [ -d "/home/student@SEC.local" ]; then rm -rf "/home/student@SEC.local"; fi'
ExecStartPost=/usr/bin/logger "Systemd Cleanup: Wiped /home/student@SEC.local"

[Install]
WantedBy=multi-user.target
EOF
chmod 644 /etc/systemd/system/cleanup-student.service
# Do not remove above
# 6. Systemd: Inactive User Cleanup (Weekly/Monthly)
cat << 'EOF' > /usr/local/bin/cleanup_old_users.sh
#!/bin/bash
set -euo pipefail

DAYS=120
DOMAIN_SUFFIX="@SEC.local"
SKIP_USER="egallen@SEC.local"
LOG_FILE="/var/log/cleanup_old_users.log"

mkdir -p "$(dirname "$LOG_FILE")"

lastlog -b "$DAYS" | awk -v suf="$DOMAIN_SUFFIX" 'NR>1 && index($0, suf){print $1}' | while read -r USER_ACCOUNT; do
    [[ -z "$USER_ACCOUNT" ]] && continue
    [[ "$USER_ACCOUNT" == "root" ]] && continue
    [[ "$USER_ACCOUNT" == "$SKIP_USER" ]] && continue

    HOME_DIR="/home/$USER_ACCOUNT"
    if [ -d "$HOME_DIR" ]; then
        pkill -u "$USER_ACCOUNT" || true
        rm -rf "$HOME_DIR"
        echo "$(date) INFO: Removed $HOME_DIR for $USER_ACCOUNT" >> "$LOG_FILE"
        logger "Inactive Cleanup: Wiped profile for $USER_ACCOUNT"
    fi
done
EOF
chmod 750 /usr/local/bin/cleanup_old_users.sh
# Test above 
cat << 'EOF' > /etc/systemd/system/delete-inactive-users.service
[Unit]
Description=Cleanup Inactive Student Profiles (>120 Days)
After=network-online.target sssd.service

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/bin/cleanup_old_users.sh
EOF

cat << 'EOF' > /etc/systemd/system/delete-inactive-users.timer
[Unit]
Description=Run Inactive User Cleanup Monthly (First Wed)

[Timer]
OnCalendar=Wed *-*-1..7 13:20:00
Persistent=true
RandomizedDelaySec=5m

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now cleanup-student.service
systemctl enable --now delete-inactive-users.timer

# 7. UI Customization (GNOME dconf)
echo ">>> Applying GNOME settings..."

# FIX: Filename changed to 'user' so GNOME reads it by default
PROFILE_FILE="/etc/dconf/profile/user"
mkdir -p /etc/dconf/profile
echo "user-db:user" > "$PROFILE_FILE"
echo "system-db:custom" >> "$PROFILE_FILE"

mkdir -p /etc/dconf/db/custom.d/locks

# FIX: Updated Snap desktop names (thonny_thonny)
cat << 'EOF' > /etc/dconf/db/custom.d/00-config
[org/gnome/settings-daemon/plugins/power]
ambient-enabled=false
idle-brightness=30
idle-dim=false
lid-close-ac-action="suspend"
lid-close-battery-action="suspend"
lid-close-suspend-with-external-monitor=true
power-button-action="interactive"
power-saver-profile-on-low-battery=false
sleep-inactive-ac-timeout=0
sleep-inactive-ac-type="nothing"
sleep-inactive-battery-timeout=0
sleep-inactive-battery-type="nothing"

[org/gnome/desktop/screensaver]
idle-activation-enabled=false
lock-delay=0
lock-enabled=false

[org/gnome/desktop/session]
idle-delay=0

[org/gnome/desktop/interface]
accent-color="purple"
color-scheme="prefer-dark"
clock-show-seconds=false
clock-show-weekday=true
show-battery-percentage=true

[org/gnome/desktop/input-sources]
sources=[("xkb", "gb")]

[org/gnome/shell/extensions/dash-to-dock]
autohide=false
dock-fixed=true
extend-height=true
dash-max-icon-size=54
dock-position="BOTTOM"

[org/gnome/shell/extensions/ding]
show-home=false

[org/gnome/shell]
favorite-apps=["google-chrome.desktop", "firefox_firefox.desktop", "libreoffice-writer.desktop", "libreoffice-calc.desktop", "org.gnome.Nautilus.desktop", "org.gnome.Terminal.desktop", "code_code.desktop", "thonny_thonny.desktop"]
EOF

# FIX: Added favorite-apps to lock file
cat << 'EOF' > /etc/dconf/db/custom.d/locks/00-lock
/org/gnome/settings-daemon/plugins/power/ambient-enabled
/org/gnome/settings-daemon/plugins/power/idle-brightness
/org/gnome/settings-daemon/plugins/power/idle-dim
/org/gnome/settings-daemon/plugins/power/lid-close-ac-action
/org/gnome/settings-daemon/plugins/power/lid-close-battery-action
/org/gnome/settings-daemon/plugins/power/lid-close-suspend-with-external-monitor
/org/gnome/settings-daemon/plugins/power/power-button-action
/org/gnome/settings-daemon/plugins/power/power-saver-profile-on-low-battery
/org/gnome/settings-daemon/plugins/power/sleep-inactive-ac-timeout
/org/gnome/settings-daemon/plugins/power/sleep-inactive-ac-type
/org/gnome/settings-daemon/plugins/power/sleep-inactive-battery-timeout
/org/gnome/settings-daemon/plugins/power/sleep-inactive-battery-type
/org/gnome/desktop/screensaver/idle-activation-enabled
/org/gnome/desktop/screensaver/lock-delay
/org/gnome/desktop/screensaver/lock-enabled
/org/gnome/desktop/session/idle-delay
/org/gnome/desktop/interface/clock-show-weekday
/org/gnome/desktop/interface/show-battery-percentage
/org/gnome/desktop/input-sources/sources
/org/gnome/shell/extensions/ding/show-home
/org/gnome/shell/favorite-apps
EOF

dconf update

# 8. Miscellaneous Cleanup
echo ">>> Performing final cleanup..."

APPS=("x11vnc.desktop" "xtigervncviewer.desktop" "debian-xterm.desktop" "debian-uxterm.desktop")
for app in "${APPS[@]}"; do
    FILE="/usr/share/applications/$app"
    if [ -f "$FILE" ]; then
        if ! grep -q "NoDisplay=true" "$FILE"; then
            echo "NoDisplay=true" >> "$FILE"
        fi
    fi
done

find /home -type f -iname "chrome-*-Default.desktop" -delete

RULES_FILE="/etc/udev/rules.d/99-microbit.rules"
if ! [ -f "$RULES_FILE" ]; then
  echo 'SUBSYSTEM=="tty", ATTRS{idVendor}=="0d28", ATTRS{idProduct}=="0204", MODE="0666"' > "$RULES_FILE"
fi
udevadm control --reload

# 9. File Associations (VS Code for TXT/CSV)
echo ">>> Setting File Associations..."
MIME_LIST="/usr/share/applications/mimeapps.list"

if [ -f "$MIME_LIST" ]; then
    if ! grep -q "\[Default Applications\]" "$MIME_LIST"; then
        echo "[Default Applications]" >> "$MIME_LIST"
    fi
    
    # Clean existing rules
    sed -i '/text\/csv/d' "$MIME_LIST"
    sed -i '/text\/plain/d' "$MIME_LIST"

    # Inject VS Code defaults
    sed -i '/\[Default Applications\]/a text/csv=code_code.desktop' "$MIME_LIST"
    sed -i '/\[Default Applications\]/a text/plain=code_code.desktop' "$MIME_LIST"
fi

echo ">>> Setup Complete! Reboot recommended."
