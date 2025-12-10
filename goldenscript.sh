#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# ==========================================
#     SCHOOL LINUX SYSTEM CONFIGURATION
#          (Ubuntu 24.04 LTS)
# ==========================================

# --- CONFIGURATION ---
# 1. ACCOUNTS
STUDENT_USER="student@SEC.local"
ADMIN_USER_1="secsuperuser"
ADMIN_USER_2="egallen@SEC.local"

# 2. WI-FI SETTINGS (CHANGE THE NAME!)
WIFI_SSID="Admin"   # <--- CHANGE THIS to your exact Wi-Fi Name
WIFI_PASS="bhd56x9064bdaz697fyc21ggh"

# 3. GROUPS & SERVER
MOCK_GROUP="mock@SEC.local lccs@SEC.local lccs1@SEC.local" 
EXAM_USER="exam@SEC.local"
TEST_USER="exam1@SEC.local"
EPOPTES_SERVER="epoptes.server.local"

# 4. SETTINGS
INACTIVE_DAYS=120
PDF_URL="https://www.examinations.ie/archive/exampapers/2022/LC219ALP000EV.pdf" 
# ---------------------

# 1. ROOT CHECK
if [ "$(id -u)" -ne 0 ]; then
  echo ">>> Error: Must run as root."
  exit 1
fi

echo ">>> Starting Final System Setup..."

# 1.5 CONNECT TO WI-FI (PRIORITY)
# We do this first so updates can run
echo ">>> Connecting to Wi-Fi ($WIFI_SSID)..."
# Try to connect. We use || true so the script doesn't crash if the SSID is wrong.
nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PASS" > /dev/null 2>&1 || echo ">>> Warning: Wi-Fi connection failed. Check SSID name or range."

# 2. UPDATES & PACKAGE MANAGEMENT
echo ">>> Preparing system..."
export DEBIAN_FRONTEND=noninteractive

# A. CLEANUP FIRST
echo ">>> Purging conflicting packages..."
snap remove thonny || true
apt-get purge -y "gnome-initial-setup" "gnome-tour" "aisleriot" "gnome-mahjongg" "gnome-mines" "gnome-sudoku" || true

# B. INSTALL SYSTEM LIBRARIES & APPS
echo ">>> Installing System & Python Libraries..."
apt-get update -q 
apt-get install -y -q \
    thonny \
    gnome-terminal \
    python3-pip \
    python3-tk \
    python3-numpy \
    python3-matplotlib \
    python3-pandas \
    python3-pygal \
    python3-pygame

# C. INSTALL CUSTOM PIP LIBRARIES
echo ">>> Installing Custom PyPI Libraries..."
pip3 install firebase compscifirebase --break-system-packages

# D. SYSTEM UPGRADE
echo ">>> Upgrading System..."
apt-get upgrade -y -q
apt-get autoremove -y -q

# E. INSTALL SNAPS
echo ">>> Installing Snaps..."
snap install --classic code || true
rm -f /usr/share/applications/code.desktop
rm -f /usr/share/applications/vscode.desktop

# 2b. PREPARE EXAM RESOURCES
echo ">>> Downloading Exam Resources..."
mkdir -p /opt/sec_exam_resources
wget -q -O /opt/sec_exam_resources/Python_Reference.pdf "$PDF_URL" || echo "Warning: PDF Download failed. Check URL."
chmod 644 /opt/sec_exam_resources/Python_Reference.pdf

# 3. UNIVERSAL CLEANUP LOGIC
cat << EOF > /usr/local/bin/universal_cleanup.sh
#!/bin/bash
TARGET_USER="\$1"
ACTION="\$2" 

clean_chrome() {
    CHROME_DIR="/home/\$TARGET_USER/.config/google-chrome"
    if [ -d "\$CHROME_DIR" ]; then
        rm -f "\$CHROME_DIR/SingletonLock" "\$CHROME_DIR/SingletonSocket" "\$CHROME_DIR/SingletonCookie"
    fi
}

wipe_immediate() {
    if [ -d "/home/\$TARGET_USER" ]; then
        pkill -u "\$TARGET_USER" || true
        sleep 1
        rm -rf "/home/\$TARGET_USER"
        logger "CLEANUP: Immediate wipe for \$TARGET_USER"
    fi
}

wipe_if_older_than_7_days() {
    if [ -d "/home/\$TARGET_USER" ]; then
        if [ \$(find "/home/\$TARGET_USER" -maxdepth 0 -mtime +7) ]; then
            pkill -u "\$TARGET_USER" || true
            rm -rf "/home/\$TARGET_USER"
            logger "CLEANUP: 7-Day limit reached. Wiped \$TARGET_USER"
        fi
    fi
}

if [ "\$ACTION" == "chrome" ]; then clean_chrome; fi
if [ "\$ACTION" == "wipe" ]; then wipe_immediate; fi
if [ "\$ACTION" == "check_7day" ]; then wipe_if_older_than_7_days; fi
EOF
chmod +x /usr/local/bin/universal_cleanup.sh

# Cron for 7-day cleanup
echo "#!/bin/bash" > /etc/cron.daily/sec_cleanup
for user in $MOCK_GROUP $EXAM_USER; do
    echo "/usr/local/bin/universal_cleanup.sh $user check_7day" >> /etc/cron.daily/sec_cleanup
done
chmod +x /etc/cron.daily/sec_cleanup

# 4. PAM MASTER CONTROLLER
echo ">>> Configuring PAM hooks..."

mkdir -p /usr/local/etc/chrome_policies
cat << EOF > /usr/local/etc/chrome_policies/student_policy.json
{
  "DefaultSearchProviderEnabled": true,
  "DefaultSearchProviderName": "Google",
  "DefaultSearchProviderSearchURL": "https://www.google.com/search?q={searchTerms}",
  "ShowFirstRunExperience": false,
  "PromotionalTabsEnabled": false,
  "BrowserSignin": 0,
  "DefaultBrowserSettingEnabled": false,
  "MetricsReportingEnabled": false,
  "SyncDisabled": true,
  "PasswordManagerEnabled": false
}
EOF

cat << EOF > /usr/local/bin/pam_hook.sh
#!/bin/bash
USER="\$PAM_USER"
TYPE="\$PAM_TYPE"

# --- USER DEFINITIONS ---
STUDENT="$STUDENT_USER"
EXAM="$EXAM_USER"
TEST="$TEST_USER"
NO_NET_USERS="$MOCK_GROUP $EXAM_USER $TEST_USER"

CHROME_MANAGED="/etc/opt/chrome/policies/managed"
POLICY_SOURCE="/usr/local/etc/chrome_policies/student_policy.json"
POLICY_DEST="\$CHROME_MANAGED/student_policy.json"
PDF_SOURCE="/opt/sec_exam_resources/Python_Reference.pdf"

# --- FUNCTIONS ---
block_internet() {
    iptables -A OUTPUT -o lo -j ACCEPT
    iptables -A OUTPUT -m owner --uid-owner "\$USER" -j REJECT
}

unblock_internet() {
    iptables -D OUTPUT -m owner --uid-owner "\$USER" -j REJECT || true
    iptables -D OUTPUT -o lo -j ACCEPT || true
}

setup_exam_files() {
    sleep 2
    DESKTOP="/home/\$USER/Desktop"
    mkdir -p "\$DESKTOP"
    if [ -f "\$PDF_SOURCE" ]; then
        cp "\$PDF_SOURCE" "\$DESKTOP/"
        chown "\$USER":"\$USER" "\$DESKTOP/Python_Reference.pdf"
        chmod 444 "\$DESKTOP/Python_Reference.pdf" 
    fi
}

# --- LOGIN LOGIC ---
if [ "\$TYPE" == "open_session" ]; then
    if [ "\$USER" == "\$STUDENT" ]; then
        mkdir -p "\$CHROME_MANAGED"
        ln -sf "\$POLICY_SOURCE" "\$POLICY_DEST"
    else
        rm -f "\$POLICY_DEST"
    fi

    if [[ " \$NO_NET_USERS " =~ " \$USER " ]]; then
        block_internet
    fi

    if [ "\$USER" == "\$EXAM" ] || [ "\$USER" == "\$TEST" ]; then
        setup_exam_files &
    fi
fi

# --- LOGOUT LOGIC ---
if [ "\$TYPE" == "close_session" ]; then
    /usr/local/bin/universal_cleanup.sh "\$USER" chrome

    if [[ " \$NO_NET_USERS " =~ " \$USER " ]]; then
        unblock_internet
    fi

    if [ "\$USER" == "\$STUDENT" ] || [ "\$USER" == "\$TEST" ]; then
        rm -f "\$POLICY_DEST"
        /usr/local/bin/universal_cleanup.sh "\$USER" wipe
    fi
fi
EOF
chmod +x /usr/local/bin/pam_hook.sh

if ! grep -q "pam_hook.sh" /etc/pam.d/common-session; then
    echo "session optional pam_exec.so /usr/local/bin/pam_hook.sh" >> /etc/pam.d/common-session
fi

# 5. INACTIVE USER CLEANUP TOOL
cat << EOF > /usr/local/bin/cleanup_old_users.sh
#!/bin/bash
set -euo pipefail
UID_MIN=1000
lastlog -b "$INACTIVE_DAYS" | awk 'NR>1 {print \$1}' | while read -r U; do
    [[ -z "\$U" ]] && continue
    USER_UID=\$(id -u "\$U" 2>/dev/null || echo 0)
    if [[ "\$USER_UID" -lt "\$UID_MIN" || "\$U" == "root" || "\$U" == "$ADMIN_USER_1" || "\$U" == "$ADMIN_USER_2" ]]; then
        continue
    fi
    logger "Inactive Cleanup: Removing account for \$U"
    pkill -u "\$U" || true
    userdel -r -f "\$U"
    logger "Inactive Cleanup: User \$U deleted successfully."
done
EOF
chmod 750 /usr/local/bin/cleanup_old_users.sh

# 6. SYSTEMD BOOT CLEANUP (SAFETY NET)
cat << EOF > /etc/systemd/system/cleanup-boot.service
[Unit]
Description=Safety Cleanup (Chrome, Student, Epoptes, Inactive)
After=network.target

[Service]
Type=oneshot
User=root
# 1. Wipe student if exists
ExecStart=/bin/bash -c 'if [ -d "/home/$STUDENT_USER" ]; then rm -rf "/home/$STUDENT_USER"; fi'
# 2. Clean Chrome locks
ExecStart=/bin/bash -c 'find /home -maxdepth 2 -name "SingletonLock" -delete'
# 3. Clean Epoptes PID
ExecStart=/bin/bash -c 'rm -f /var/run/epoptes-client.pid'
# 4. AUTO-HEAL: Fetch Epoptes Cert if missing
ExecStart=/bin/bash -c 'if [ ! -f /etc/epoptes/server.crt ]; then epoptes-client -c || true; fi'
# 5. CRITICAL: Run Inactive User Cleanup (Failsafe)
ExecStart=/usr/local/bin/cleanup_old_users.sh
ExecStartPost=/usr/bin/logger "Systemd: Boot cleanup complete"

[Install]
WantedBy=multi-user.target
EOF
chmod 644 /etc/systemd/system/cleanup-boot.service
systemctl daemon-reload
systemctl enable --now cleanup-boot.service

# 7. UI ENFORCEMENT
echo ">>> Generating UI Enforcer script..."
if [ -f "/var/lib/snapd/desktop/applications/code_code.desktop" ]; then CODE="code_code.desktop"; else CODE="code.desktop"; fi
THONNY="org.thonny.Thonny.desktop"

cat << EOF > /usr/local/bin/force_ui.sh
#!/bin/bash
if [ "\$USER" == "$ADMIN_USER_1" ] || [ "\$USER" == "$ADMIN_USER_2" ]; then exit 0; fi

RESTRICTED_USERS="$MOCK_GROUP $EXAM_USER $TEST_USER"
sleep 3
pactl set-sink-mute @DEFAULT_SINK@ 1 > /dev/null 2>&1 || true
powerprofilesctl set performance || true
gsettings set org.gnome.desktop.screensaver lock-enabled false
gsettings set org.gnome.desktop.session idle-delay 0
gsettings set org.gnome.desktop.lockdown disable-printing true
gsettings set org.gnome.desktop.lockdown disable-print-setup true

if [[ " \$RESTRICTED_USERS " =~ " \$USER " ]]; then
    gsettings set org.gnome.desktop.interface gtk-theme 'Yaru'
    gsettings set org.gnome.desktop.interface icon-theme 'Yaru'
    gsettings set org.gnome.shell favorite-apps "['org.gnome.Nautilus.desktop', '$THONNY']"
    gsettings set org.gnome.desktop.lockdown disable-command-line true
else
    # STUDENT MODE: Added Terminal to the dock
    gsettings set org.gnome.desktop.interface gtk-theme 'Yaru-purple'
    gsettings set org.gnome.desktop.interface icon-theme 'Yaru-purple'
    gsettings set org.gnome.shell favorite-apps "['google-chrome.desktop', 'firefox_firefox.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Terminal.desktop', '$CODE', '$THONNY']"
fi

for schema in "org.gnome.shell.extensions.dash-to-dock" "org.gnome.shell.extensions.ubuntu-dock"; do
    gsettings set \$schema dock-position 'BOTTOM'
    gsettings set \$schema autohide true
    gsettings set \$schema extend-height false
    gsettings set \$schema dash-max-icon-size 54
    gsettings set \$schema dock-fixed false
done
gsettings set org.gnome.shell welcome-dialog-last-shown-version '999999'
EOF
chmod +x /usr/local/bin/force_ui.sh

cat << EOF > /etc/xdg/autostart/force_ui.desktop
[Desktop Entry]
Type=Application
Name=Force UI
Exec=/usr/local/bin/force_ui.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

# 8. MISC FIXES (INCLUDES SINGLE USER ENFORCEMENT)
echo ">>> Applying final fixes..."
cat << EOF > /etc/sysctl.d/99-lab-keepalive.conf
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 3
EOF
sysctl --system

# Disable Fast User Switching (Enforces Single User)
mkdir -p /etc/dconf/profile
echo -e "user-db:user\nsystem-db:local" > /etc/dconf/profile/user
mkdir -p /etc/dconf/db/local.d
echo -e "[org/gnome/desktop/lockdown]\ndisable-user-switching=true" > /etc/dconf/db/local.d/00-disable-switching
dconf update

# Hide VNC & Terminal Icons (Optional: We un-hid Terminal in dock, but hide the icon in menu if desired)
APPS=("x11vnc.desktop" "xtigervncviewer.desktop" "debian-xterm.desktop" "debian-uxterm.desktop")
for app in "${APPS[@]}"; do
    FILE="/usr/share/applications/$app"
    [ -f "$FILE" ] && echo "NoDisplay=true" >> "$FILE"
done

# Microbit Rules
echo 'SUBSYSTEM=="tty", ATTRS{idVendor}=="0d28", ATTRS{idProduct}=="0204", MODE="0666"' > "/etc/udev/rules.d/99-microbit.rules"
udevadm control --reload

# File Associations & DEFAULT BROWSER FIX
MIME="/usr/share/applications/mimeapps.list"
if [ -f "$MIME" ]; then
    grep -q "\[Default Applications\]" "$MIME" || echo "[Default Applications]" >> "$MIME"
    sed -i '/text\/csv/d' "$MIME"
    sed -i '/text\/plain/d' "$MIME"
    # Ensure Chrome is default for Web to stop OS popups
    sed -i '/text\/html/d' "$MIME"
    sed -i '/x-scheme-handler\/http/d' "$MIME"
    sed -i '/x-scheme-handler\/https/d' "$MIME"
    
    sed -i '/\[Default Applications\]/a text/csv=code_code.desktop' "$MIME"
    sed -i '/\[Default Applications\]/a text/plain=code_code.desktop' "$MIME"
    sed -i '/\[Default Applications\]/a text/html=google-chrome.desktop' "$MIME"
    sed -i '/\[Default Applications\]/a x-scheme-handler/http=google-chrome.desktop' "$MIME"
    sed -i '/\[Default Applications\]/a x-scheme-handler/https=google-chrome.desktop' "$MIME"
fi

# 9. SCHEDULED MAINTENANCE & SMART SHUTDOWN
echo ">>> Scheduling Smart Shutdown & Maintenance..."

# A. Create the Maintenance/Shutdown Script
cat << 'EOF' > /usr/local/bin/smart_shutdown.sh
#!/bin/bash
set -u

# --- CONFIG ---
CLEANUP_DAY=2  # 2 = Tuesday
# ----------------

# 1. NOTIFY USERS (5 Minute Warning)
MSG="School day ending. System will install updates and shut down in 5 minutes. Please save your work."
wall "$MSG"
LOGGED_USER=$(who | grep ':0' | awk '{print $1}' | head -n 1)
if [ -n "$LOGGED_USER" ]; then
    USER_ID=$(id -u "$LOGGED_USER")
    sudo -u "$LOGGED_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/"$USER_ID"/bus notify-send "SYSTEM SHUTDOWN" "$MSG" --urgency=
