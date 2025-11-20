#!/bin/bash

# check if the script is running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "this script must be running as root - exiting"
  exit 1
fi

# update repository and upgrade packages
apt update && apt upgrade -y

# uninstall packages
apt purge code -y
apt purge thonny -y

# install packages
snap install --classic code
snap install thonny

# uninstall gnome-initial-setup
apt remove --autoremove gnome-initial-setup -y

# uninstall zenity to fix file saving
apt purge zenity -y

# initialise maintenance scripts
CLEARACCOUNTS_SCRIPT='#!/bin/bash
set -euo pipefail

LOG_FILE="/var/log/clearaccounts.log"
mkdir -p "$(dirname "$LOG_FILE")"

DAYS_LIMIT=120
SECONDS_LIMIT=$(( DAYS_LIMIT * 86400 ))

epoch_now=$(date +%s)

for dir in /home/*; do
  [[ -d "$dir" ]] || continue

  user="${dir##*/}"
  [[ "$user" == "*" ]] && continue
  [[ "$user" == "secsuperuser" ]] && continue
  [[ "$user" == "egallen@SEC.local" ]] && continue

  line=$(last -F -- "$user" 2>/dev/null | grep "login screen" | head -n1 || true)
  if [[ -z "$line" ]]; then
    timestamp="$(date +"%d-%m-%Y %H:%M:%S")"
    echo "$timestamp ERROR: no login screen record found for $user" >> "$LOG_FILE"
    continue
  fi

  collapsed=$(echo "$line" | tr -s " ")
  date=$(echo "$collapsed" | awk '\''{ for(i=5;i<=9;i++) printf "%s%s", $i, (i<9?" ":""); }'\'')
  if [[ -z "$date" ]]; then
    timestamp="$(date +"%d-%m-%Y %H:%M:%S")"
    echo "$timestamp ERROR: could not extract timestamp from $line" >> "$LOG_FILE"
    continue
  fi

  if ! epoch_last=$(date -d "$date" +%s 2>/dev/null); then
    timestamp="$(date +"%d-%m-%Y %H:%M:%S")"
    echo "$timestamp ERROR: failed to parse date $date for $user" >> "$LOG_FILE"
    continue
  fi

  seconds_passed=$(( epoch_now - epoch_last ))

  timestamp="$(date +"%d-%m-%Y %H:%M:%S")"
  echo "$timestamp INFO: user=$user seconds_passed=$seconds_passed days_passed=$(( seconds_passed / 86400 ))" >> "$LOG_FILE"

  if (( seconds_passed > SECONDS_LIMIT )); then
    timestamp="$(date +"%d-%m-%Y %H:%M:%S")"
    echo "$timestamp INFO: $user has not logged in $DAYS_LIMIT days" >> "$LOG_FILE"
    rm -fr "$dir"
    timestamp="$(date +"%d-%m-%Y %H:%M:%S")"
    echo "$timestamp INFO: $user home directory has been cleared" >> "$LOG_FILE"
  fi
done'

CLEARSTUDENT_SCRIPT='TARGET_USER="student@SEC.local"
if [ "$PAM_USER" = "$TARGET_USER" ]; then
    if [ -d "/home/$TARGET_USER" ]; then
        pkill -u "$TARGET_USER"
        rm -rf "/home/$TARGET_USER"
    fi
fi'

CRON_TEMPLATE='
# custom scripts
@reboot apt update && apt upgrade -y && apt autoremove -y
@reboot /bin/bash -c '\''for user in /home/*; do /bin/rm -rf "$user/.config/google-chrome/Singleton*"; done'\''
15 16 * * * root shutdown -h now
02 16 * * * apt update && apt upgrade -y && apt autoremove -y
10 16 * * *  /bin/bash -c '\''for user in /home/*; do /bin/rm -rf "$user/.config/google-chrome/Singleton*"; done'\'''


mkdir /home/secsuperuser/scripts

echo "$CLEARACCOUNTS_SCRIPT" > /home/secsuperuser/scripts/clearaccounts.sh
chmod +x /home/secsuperuser/scripts/clearaccounts.sh

echo "$CLEARSTUDENT_SCRIPT" > /usr/local/bin/clearstudent.sh
echo "session optional pam_exec.so type=close_session /usr/local/bin/clearstudent.sh" >> /etc/pam.d/common-session
chmod +x /usr/local/bin/clearstudent.sh

echo "$CRON_TEMPLATE" > /etc/crontab

# create systemd unit to wipe student profile at boot
SERVICE_UNIT='[Unit]
Description=Wipe Student AD Profile on Boot
# Wait for network and SSSD to be ready
After=network-online.target sssd.service systemd-user-sessions.service
Wants=network-online.target

[Service]
Type=oneshot
User=root
# Remove student home if present
ExecStart=/bin/bash -c '\''if [ -d "/home/student@SEC.local" ]; then rm -rf "/home/student@SEC.local"; fi'\''
ExecStartPost=/usr/bin/logger "Systemd Cleanup: Wiped /home/student@SEC.local"

[Install]
WantedBy=multi-user.target
'

echo "$SERVICE_UNIT" > /etc/systemd/system/cleanup-student.service
chmod 644 /etc/systemd/system/cleanup-student.service

# reload systemd, enable and start the service now (runs on this boot and subsequent boots)
systemctl daemon-reload
systemctl enable --now cleanup-student.service

# add cleanup for inactive domain users (skip egallen@SEC.local)
CLEANUP_OLD_USERS_SCRIPT='#!/bin/bash
set -euo pipefail

DAYS=120
DOMAIN_SUFFIX="@SEC.local"
SKIP_USER="egallen@SEC.local"
LOG_FILE="/var/log/cleanup_old_users.log"
mkdir -p "$(dirname "$LOG_FILE")"

# list accounts with DOMAIN_SUFFIX inactive for > DAYS using lastlog
# awk extracts username column; skip header and the SKIP_USER
lastlog -b "$DAYS" | awk -v suf="$DOMAIN_SUFFIX" '\''NR>1 && index($0, suf){print $1}'\'' | while read -r USER_ACCOUNT; do
    # safety: skip empty and reserved accounts
    [[ -z "$USER_ACCOUNT" ]] && continue
    [[ "$USER_ACCOUNT" == "root" ]] && continue
    [[ "$USER_ACCOUNT" == "'"$SKIP_USER"'" ]] && continue

    HOME_DIR="/home/$USER_ACCOUNT"
    if [ -d "$HOME_DIR" ]; then
        echo "$(date -u +"%Y-%m-%d %T UTC") INFO: Processing $USER_ACCOUNT (home: $HOME_DIR)" >> "$LOG_FILE"

        # kill any remaining processes and remove home dir
        pkill -u "$USER_ACCOUNT" || true
        rm -rf "$HOME_DIR"

        echo "$(date -u +"%Y-%m-%d %T UTC") INFO: Removed $HOME_DIR for $USER_ACCOUNT" >> "$LOG_FILE"
        logger "Inactive Cleanup: Wiped profile for $USER_ACCOUNT (Inactive > $DAYS days)"
    fi
done
'

echo "$CLEANUP_OLD_USERS_SCRIPT" > /usr/local/bin/cleanup_old_users.sh
chmod 750 /usr/local/bin/cleanup_old_users.sh
chown root:root /usr/local/bin/cleanup_old_users.sh

# create systemd service (one-shot)
DELETE_INACTIVE_SERVICE='[Unit]
Description=Cleanup Inactive Student Profiles (>120 Days)
After=network-online.target sssd.service systemd-user-sessions.service
Wants=network-online.target

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/bin/cleanup_old_users.sh
'

echo "$DELETE_INACTIVE_SERVICE" > /etc/systemd/system/delete-inactive-users.service
chmod 644 /etc/systemd/system/delete-inactive-users.service

# create a timer to run monthly on the first Wednesday at 01:20
DELETE_INACTIVE_TIMER='[Unit]
Description=Monthly cleanup (first Wednesday) of inactive student profiles (>120 Days)

[Timer]
# First Wednesday of every month at 13:20
OnCalendar=Wed *-*-1..7 13:20:00
Persistent=true
# Add a small randomized delay to avoid load spikes if many machines run at once
RandomizedDelaySec=30m

[Install]
WantedBy=timers.target
'

echo "$DELETE_INACTIVE_TIMER" > /etc/systemd/system/delete-inactive-users.timer
chmod 644 /etc/systemd/system/delete-inactive-users.timer

# reload systemd and enable timer
systemctl daemon-reload
systemctl enable --now delete-inactive-users.timer


# initialise customised ui
CONFIG='[org/gnome/settings-daemon/plugins/power]
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
show-home=false'

LOCK='# [org/gnome/settings-daemon/plugins/power]
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

# [org/gnome/desktop/screensaver]
/org/gnome/desktop/screensaver/idle-activation-enabled
/org/gnome/desktop/screensaver/lock-delay
/org/gnome/desktop/screensaver/lock-enabled

# [org/gnome/desktop/session]
/org/gnome/desktop/session/idle-delay

# [org/gnome/desktop/interface]
/org/gnome/desktop/interface/clock-show-weekday
/org/gnome/desktop/interface/show-battery-percentage

# [org/gnome/desktop/input-sources]
/org/gnome/desktop/input-sources/sources

# [org/gnome/shell/extensions/dash-to-dock]
#/org/gnome/shell/extensions/dash-to-dock/autohide
#/org/gnome/shell/extensions/dash-to-dock/dock-fixed
#/org/gnome/shell/extensions/dash-to-dock/extend-height
#/org/gnome/shell/extensions/dash-to-dock/dash-max-icon-size
#/org/gnome/shell/extensions/dash-to-dock/dock-position

[org/gnome/shell]
favorite-apps=["google-chrome.desktop", "firefox_firefox.desktop", "libreoffice-writer.desktop", "libreoffice-calc.desktop", "org.gnome.Nautilus.desktop", "org.gnome.Terminal.desktop", "code_code.desktop", "org.thonny.Thonny.desktop"]

# [org/gnome/shell/extensions/ding]
/org/gnome/shell/extensions/ding/show-home'

PROFILE_FILE="/etc/dconf/profile/custom"
mkdir -p /etc/dconf/profile
echo "user-db:user" > "$PROFILE_FILE"
echo "system-db:custom" >> "$PROFILE_FILE"

DB_FILE="/etc/dconf/db/custom.d/00-config"
DB_LOCK_FILE="/etc/dconf/db/custom.d/locks/00-lock"
sudo mkdir -p /etc/dconf/db/custom.d/locks
echo "$CONFIG" > "$DB_FILE"
echo "$LOCK" > "$DB_LOCK_FILE"

# hide apps from start menu
APPS=("x11vnc.desktop" "xtigervncviewer.desktop" "debian-xterm.desktop" "debian-uxterm.desktop")
for app in "${APPS[@]}"
do
    echo "NoDisplay=true" >> "/usr/share/applications/$app"
done

# delete all chrome shortcuts
find /home -type f -iname "chrome-*-Default.desktop" -delete

# microbit serial access
RULES_FILE="/etc/udev/rules.d/99-microbit.rules"
VENDOR_ID="0d28"
PRODUCT_ID="0204"

if ! [ -f "$RULES_FILE" ]; then
  echo "SUBSYSTEM==\"tty\", ATTRS{idVendor}==\"$VENDOR_ID\", ATTRS{idProduct}==\"$PRODUCT_ID\", MODE=\"0666\"" > "$RULES_FILE"
fi

udevadm control --reload

# final cleanup
apt autoremove -y