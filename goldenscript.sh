#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# ==========================================
#      SCHOOL LINUX SYSTEM CONFIGURATION
#          (Ubuntu 24.04 LTS)
# ==========================================

# --- CONFIGURATION ---
# 1. ACCOUNTS
STUDENT_USER="student@SEC.local"
ADMIN_USER_1="secsuperuser"
ADMIN_USER_2="egallen@SEC.local"

# 2. WI-FI SETTINGS
WIFI_SSID="Admin"
WIFI_PASS="bhd56x9064bdaz697fyc21ggh"

# 3. GROUPS & SERVER
# Space-separated list of accounts used for special exam modes
# NOTE: The restrictions in this script now apply to ALL non-admins automatically.
MOCK_GROUP="mock@SEC.local lccs@SEC.local lccs1@SEC.local" 
EXAM_USER="exam@SEC.local"
TEST_USER="exam1@SEC.local"
EPOPTES_SERVER="epoptes.server.local"

# 4. SETTINGS
INACTIVE_DAYS=120
PDF_URL="https://www.examinations.ie/docs/viewer.php?q=e5c7ee46cecf19bc20023e32f0664b6b6a152c15" 
# ---------------------

# 1. ROOT CHECK
if [ "$(id -u)" -ne 0 ]; then
  echo ">>> Error: Must run as root."
  exit 1
fi

echo ">>> Starting Final System Setup..."

# 1.5 CONNECT TO WI-FI (Aggressive Mode)
echo ">>> Connecting to Wi-Fi ($WIFI_SSID)..."
nmcli radio wifi on
nmcli connection delete "$WIFI_SSID" > /dev/null 2>&1 || true
nmcli device wifi rescan || true
sleep 3
nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PASS" || echo ">>> Warning: Wi-Fi connection failed. Check signal/range."

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
# Define strict offline users
NO_NET_USERS="$MOCK_GROUP $EXAM_USER $TEST_USER"

CHROME_MANAGED="/etc/opt/chrome/policies/managed"
POLICY_SOURCE="/usr/local/etc/chrome_policies/student_policy.json"
POLICY_DEST="\$CHROME_MANAGED/student_policy.json"
PDF_SOURCE="/opt/sec_exam_resources/Python_Reference.pdf"

# --- FUNCTIONS ---
block_internet() {
    iptables -I OUTPUT 1 -o lo -j ACCEPT
    iptables -I OUTPUT 2 -d 192.168.0.0/16 -j ACCEPT
    iptables -I OUTPUT 3 -d 10.0.0.0/8 -j ACCEPT
    iptables -I OUTPUT 4 -d 172.16.0.0/12 -j ACCEPT
    iptables -I OUTPUT 5 -m owner --uid-owner "\$USER" -j REJECT
    ip6tables -I OUTPUT 1 -m owner --uid-owner "\$USER" -j REJECT
}

unblock_internet() {
    iptables -D OUTPUT -m owner --uid-owner "\$USER" -j REJECT || true
    ip6tables -D OUTPUT -m owner --uid-owner "\$USER" -j REJECT || true
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
    # Apply Chrome Policy to Student
    if [ "\$USER" == "\$STUDENT" ]; then
        mkdir -p "\$CHROME_MANAGED"
        ln -sf "\$POLICY_SOURCE" "\$POLICY_DEST"
    else
        rm -f "\$POLICY_DEST"
    fi

    # Block Internet for Mock/Exam users
    if [[ " \$NO_NET_USERS " =~ " \$USER " ]]; then
        block_internet
        logger "SEC_SCRIPT: Internet Blocked for \$USER"
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

# 6. SYSTEMD BOOT CLEANUP
cat << EOF > /etc/systemd/system/cleanup-boot.service
[Unit]
Description=Safety Cleanup (Chrome, Student, Epoptes, Inactive)
After=network.target

[Service]
Type=oneshot
User=root
ExecStart=/bin/bash -c 'if [ -d "/home/$STUDENT_USER" ]; then rm -rf "/home/$STUDENT_USER"; fi'
ExecStart=/bin/bash -c 'find /home -maxdepth 2 -name "SingletonLock" -delete'
ExecStart=/bin/bash -c 'rm -f /var/run/epoptes-client.pid'
ExecStart=/bin/bash -c 'if [ ! -f /etc/epoptes/server.crt ]; then epoptes-client -c || true; fi'
ExecStart=/usr/local/bin/cleanup_old_users.sh
ExecStartPost=/usr/bin/logger "Systemd: Boot cleanup complete"

[Install]
WantedBy=multi-user.target
EOF
chmod 644 /etc/systemd/system/cleanup-boot.service
systemctl daemon-reload
systemctl enable --now cleanup-boot.service

# 7. UI ENFORCEMENT (UPDATED FOR MUTE & RESTRICTIONS)
echo ">>> Generating UI Enforcer script..."
if [ -f "/var/lib/snapd/desktop/applications/code_code.desktop" ]; then CODE="code_code.desktop"; else CODE="code.desktop"; fi
THONNY="org.thonny.Thonny.desktop"

cat << EOF > /usr/local/bin/force_ui.sh
#!/bin/bash

# --- EXEMPT ADMINS ---
# Any user not in this list will be restricted.
if [ "\$USER" == "$ADMIN_USER_1" ] || [ "\$USER" == "$ADMIN_USER_2" ]; then
    exit 0
fi

# --- APPLY TO ALL NON-ADMINS ---
sleep 3

# 1. MUTE AUDIO ON LOGIN
# Forces audio mute immediately upon login for non-admins
pactl set-sink-mute @DEFAULT_SINK@ 1 > /dev/null 2>&1 || true

# 2. POWER & LOCKDOWN
powerprofilesctl set performance || true
gsettings set org.gnome.desktop.screensaver lock-enabled false
gsettings set org.gnome.desktop.session idle-delay 0
gsettings set org.gnome.desktop.lockdown disable-printing true
gsettings set org.gnome.desktop.lockdown disable-print-setup true
gsettings set org.gnome.desktop.lockdown disable-user-switching true

# 3. IDENTIFY MODE (EXAM vs STANDARD)
RESTRICTED_USERS="$MOCK_GROUP $EXAM_USER $TEST_USER"

if [[ " \$RESTRICTED_USERS " =~ " \$USER " ]]; then
    # === STRICT EXAM MODE ===
    gsettings set org.gnome.desktop.interface gtk-theme 'Yaru'
    gsettings set org.gnome.desktop.interface icon-theme 'Yaru'
    
    # DOCK: ONLY THONNY
    gsettings set org.gnome.shell favorite-apps "['$THONNY']"
    
    # DISABLE "SUPER" KEY & APP GRID
    gsettings set org.gnome.mutter overlay-key ''
    gsettings set org.gnome.shell.keybindings toggle-overview "[]"
    
    for schema in "org.gnome.shell.extensions.dash-to-dock" "org.gnome.shell.extensions.ubuntu-dock"; do
        gsettings set \$schema show-show-apps-button false
    done

    # DISABLE RUN COMMAND
    gsettings set org.gnome.desktop.lockdown disable-command-line true
else
    # === STANDARD STUDENT/USER MODE ===
    # (Applies to student@, a@, b@, etc.)
    gsettings set org.gnome.mutter overlay-key 'Super_L'
    gsettings set org.gnome.shell.keybindings toggle-overview "['<Super>s']"
    
    gsettings set org.gnome.desktop.interface gtk-theme 'Yaru-purple'
    gsettings set org.gnome.desktop.interface icon-theme 'Yaru-purple'
    gsettings set org.gnome.shell favorite-apps "['google-chrome.desktop', 'firefox_firefox.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Terminal.desktop', '$CODE', '$THONNY']"
    
    for schema in "org.gnome.shell.extensions.dash-to-dock" "org.gnome.shell.extensions.ubuntu-dock"; do
        gsettings set \$schema show-show-apps-button true
    done
fi

# 4. DOCK LAYOUT (Universal)
for schema in "org.gnome.shell.extensions.dash-to-dock" "org.gnome.shell.extensions.ubuntu-dock"; do
    gsettings set \$schema dock-position 'BOTTOM'
    gsettings set \$schema autohide true
    gsettings set
