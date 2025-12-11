#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# ==========================================
#       SCHOOL LINUX SYSTEM CONFIGURATION
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

# 2. UPDATES & PACKAGE MANAGEMENT
echo ">>> Preparing system..."
export DEBIAN_FRONTEND=noninteractive

# A. CLEANUP FIRST
echo ">>> Purging conflicting packages..."
# Ensure Thonny SNAP is removed so we can use the APT version
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

# 2c. PRIVACY LOCKDOWN
echo ">>> Locking down User Privacy..."

# 1. Configure default permission for NEW users (UMASK 077 = 700 permissions)
sed -i 's/^UMASK.*/UMASK 077/g' /etc/login.defs
sed -i 's/^#*DIR_MODE.*/DIR_MODE=0700/g' /etc/adduser.conf

# 2. Configure PAM to use strict umask if it creates home dirs
if grep -q "pam_mkhomedir.so" /etc/pam.d/common-session; then
    sed -i 's/pam_mkhomedir.so.*/pam_mkhomedir.so skel=\/etc\/skel\/ umask=0077/' /etc/pam.d/common-session
fi

# 3. Force permission fix on ALL CURRENT existing home directories
# This ensures student A cannot see student B's files right now.
echo ">>> Applying strict permissions to existing home folders..."
chmod 700 /home/*

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
        # 1. Kill processes gently then forcefully
        pkill -u "\$TARGET_USER" --signal 15 || true
        sleep 1
        pkill -u "\$TARGET_USER" --signal 9 || true
        
        # 2. Wait for locks to release
        sleep 2
        
        # 3. Remove directory
        rm -rf "/home/\$TARGET_USER"
        
        logger "CLEANUP: Immediate wipe for \$TARGET_USER completed (Secure Mode)."
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
  "PasswordManagerEnabled": false,
  "PrintingEnabled": false
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
    if [ "\$USER" == "\$STUDENT" ]; then
        mkdir -p "\$CHROME_MANAGED"
        ln -sf "\$POLICY_SOURCE" "\$POLICY_DEST"
    else
        rm -f "\$POLICY_DEST"
    fi

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
    
    # 1. Clean Chrome locks immediately (low risk)
    /usr/local/bin/universal_cleanup.sh "\$USER" chrome

    # 2. Unblock internet
    if [[ " \$NO_NET_USERS " =~ " \$USER " ]]; then
        unblock_internet
    fi

    # 3. WIPE HOME DIR (DELAYED & DETACHED)
    # Using systemd-run creates a background task that survives the PAM teardown.
    # We wait 5 seconds to allow GDM/GNOME to finish writing logout files.
    if [ "\$USER" == "\$STUDENT" ] || [ "\$USER" == "\$TEST" ]; then
        rm -f "\$POLICY_DEST"
        systemd-run --unit="cleanup-\${USER}-\$(date +%s)" \
                    --service-type=oneshot \
                    /bin/bash -c "sleep 5; /usr/local/bin/universal_cleanup.sh '\$USER' wipe"
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
# 7. UI ENFORCEMENT (HYBRID METHOD)
echo ">>> Locking down Global UI Settings (Instant & Permanent)..."

# A. APPLY GLOBAL LOCKS (Zero Lag)
# These settings apply instantly before the desktop even loads.

mkdir -p /etc/dconf/profile
mkdir -p /etc/dconf/db/local.d/locks

# 1. Define the 'user' profile to include a 'local' system database
echo -e "user-db:user\nsystem-db:local" > /etc/dconf/profile/user

# 2. Create the System-Wide Settings (Applied to EVERYONE instantly)
cat << EOF > /etc/dconf/db/local.d/00-school-defaults
[org/gnome/desktop/sound]
mute-output-volume=true

[org/gnome/desktop/lockdown]
disable-printing=true
disable-print-setup=true
disable-user-switching=true

[org/gnome/desktop/interface]
clock-show-seconds=true
enable-hot-corners=true

[org/gnome/desktop/calendar]
show-weekdate=true

[org/gnome/mutter]
edge-tiling=true
EOF

# 3. LOCK these settings so students cannot change them
cat << EOF > /etc/dconf/db/local.d/locks/school-locks
/org/gnome/desktop/sound/mute-output-volume
/org/gnome/desktop/lockdown/disable-printing
/org/gnome/desktop/lockdown/disable-print-setup
/org/gnome/desktop/interface/clock-show-seconds
/org/gnome/desktop/lockdown/disable-user-switching
EOF

# 4. Update the binary database
dconf update


# B. GENERATE USER LOGIC SCRIPT (Low Lag)
# This only runs for visual changes (Icons/Theme) that depend on WHO logged in.

echo ">>> Generating Conditional UI Script..."

# --- APP DETECTION ---
# Detect Code path (Snap)
if [ -f "/var/lib/snapd/desktop/applications/code_code.desktop" ]; then CODE="code_code.desktop"; else CODE="code.desktop"; fi
# Detect Firefox path (Snap vs Apt)
if [ -f "/var/lib/snapd/desktop/applications/firefox_firefox.desktop" ]; then FIREFOX="firefox_firefox.desktop"; else FIREFOX="firefox.desktop"; fi

THONNY="org.thonny.Thonny.desktop"

cat << EOF > /usr/local/bin/force_ui.sh
#!/bin/bash

# Admins skip everything
if [ "\$USER" == "$ADMIN_USER_1" ] || [ "\$USER" == "$ADMIN_USER_2" ]; then exit 0; fi

# DEFINE VARIABLES
RESTRICTED_USERS="$MOCK_GROUP $EXAM_USER $TEST_USER"

# Wait a split second to ensure the user session DB is writable
sleep 1

if [[ " \$RESTRICTED_USERS " =~ " \$USER " ]]; then
    # === EXAM MODE ===
    # Visuals
    gsettings set org.gnome.desktop.interface gtk-theme 'Yaru'
    gsettings set org.gnome.shell favorite-apps "['$THONNY']"
    
    # Restrictions
    gsettings set org.gnome.mutter overlay-key ''
    gsettings set org.gnome.shell.keybindings toggle-overview "[]"
    gsettings set org.gnome.desktop.lockdown disable-command-line true
    
    # Hide "Show Apps" button (The 9 dots)
    for schema in "org.gnome.shell.extensions.dash-to-dock" "org.gnome.shell.extensions.ubuntu-dock"; do
        gsettings set \$schema show-show-apps-button false
    done

else
    # === STUDENT MODE ===
    # Visuals
    gsettings set org.gnome.desktop.interface gtk-theme 'Yaru-purple'
    # Added Firefox at start, followed by Chrome, Nautilus, Terminal, Code, Thonny
    gsettings set org.gnome.shell favorite-apps "['$FIREFOX', 'google-chrome.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Terminal.desktop', '$CODE', '$THONNY']"
    
    # Reset Restrictions (In case they were stuck from a previous exam session)
    gsettings set org.gnome.mutter overlay-key 'Super_L'
    gsettings set org.gnome.shell.keybindings toggle-overview "['<Super>s']"
    gsettings set org.gnome.desktop.lockdown disable-command-line false
    
    # Ensure Apps Button is VISIBLE
    for schema in "org.gnome.shell.extensions.dash-to-dock" "org.gnome.shell.extensions.ubuntu-dock"; do
        gsettings set \$schema show-show-apps-button true
    done
fi

# Dock Styling (Apply to everyone)
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

# C. AUTOSTART THE LOGIC SCRIPT
cat << EOF > /etc/xdg/autostart/force_ui.desktop
[Desktop Entry]
Type=Application
Name=Force UI
Exec=/usr/local/bin/force_ui.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
# 8. MISC FIXES
echo ">>> Applying final fixes..."

# A. TCP Keepalive
cat << EOF > /etc/sysctl.d/99-lab-keepalive.conf
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 3
EOF
sysctl --system

# B. Disable Fast User Switching
mkdir -p /etc/dconf/profile
echo -e "user-db:user\nsystem-db:local" > /etc/dconf/profile/user
mkdir -p /etc/dconf/db/local.d
echo -e "[org/gnome/desktop/lockdown]\ndisable-user-switching=true" > /etc/dconf/db/local.d/00-disable-switching
dconf update

# C. Hide VNC & Terminal Icons
APPS=("x11vnc.desktop" "xtigervncviewer.desktop" "debian-xterm.desktop" "debian-uxterm.desktop")
for app in "${APPS[@]}"; do
    FILE="/usr/share/applications/$app"
    [ -f "$FILE" ] && echo "NoDisplay=true" >> "$FILE"
done

# D. Microbit Rules
echo 'SUBSYSTEM=="tty", ATTRS{idVendor}=="0d28", ATTRS{idProduct}=="0204", MODE="0666"' > "/etc/udev/rules.d/99-microbit.rules"
udevadm control --reload

# E. FILE ASSOCIATIONS (Fixed)
# 1. Identify Apps
if [ -f "/var/lib/snapd/desktop/applications/code_code.desktop" ]; then
    CODE_APP="code_code.desktop"
else
    CODE_APP="code.desktop"
fi
THONNY_APP="org.thonny.Thonny.desktop"

# 2. Target XDG System Config
MIME="/etc/xdg/mimeapps.list"
mkdir -p /etc/xdg
touch "$MIME"

# Ensure Header
grep -q "\[Default Applications\]" "$MIME" || echo "[Default Applications]" >> "$MIME"

# Clean old entries
sed -i '/text\/csv/d' "$MIME"
sed -i '/text\/plain/d' "$MIME"
sed -i '/text\/html/d' "$MIME"
sed -i '/x-scheme-handler\/http/d' "$MIME"
sed -i '/x-scheme-handler\/https/d' "$MIME"
sed -i '/text\/x-python/d' "$MIME"
sed -i '/application\/x-python-code/d' "$MIME"

# Inject Defaults
cat << EOF >> "$MIME"
text/csv=$CODE_APP
text/plain=$CODE_APP
text/x-python=$THONNY_APP
application/x-python-code=$THONNY_APP
text/html=google-chrome.desktop
x-scheme-handler/http=google-chrome.desktop
x-scheme-handler/https=google-chrome.desktop
EOF
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
    sudo -u "$LOGGED_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/"$USER_ID"/bus notify-send "SYSTEM SHUTDOWN" "$MSG" --urgency=critical --icon=system-shutdown || true
fi

# 2. WAIT 5 MINUTES
sleep 300

# 3. PREVENT SLEEP (Keep system alive for updates)
systemd-inhibit --what=sleep --mode=block --why="Installing Updates" bash -c '

    # 4. RUN SYSTEM UPDATES
    logger "SmartShutdown: Starting system updates..."
    export DEBIAN_FRONTEND=noninteractive
    
    # Update Apt
    apt-get update -q
    apt-get upgrade -y -q
    apt-get autoremove -y -q
    apt-get clean -q
    
    # Update Snaps (VS Code only now)
    pkill -f "code" || true
    pkill -f "thonny" || true
    snap refresh || true

    # 5. TUESDAY CLEANUP CHECK
    if [ "$(date +%u)" -eq "$CLEANUP_DAY" ]; then
        logger "SmartShutdown: It is Tuesday. Running Inactive User Cleanup..."
        if [ -f /usr/local/bin/cleanup_old_users.sh ]; then
            /usr/local/bin/cleanup_old_users.sh
        fi
    fi
'

# 6. SHUTDOWN
logger "SmartShutdown: Maintenance complete. Powering off."
poweroff
EOF
chmod 750 /usr/local/bin/smart_shutdown.sh

# B. Create the Schedule (Cron)
cat << EOF > /etc/cron.d/school_shutdown_schedule
# m h dom mon dow user  command
10 16 * * 1-4 root /usr/local/bin/smart_shutdown.sh
25 13 * * 5   root /usr/local/bin/smart_shutdown.sh
EOF
chmod 644 /etc/cron.d/school_shutdown_schedule

# 10. FINAL POLISH
echo ">>> Applying final polish..."

# A. Disable Software Update Notifications
cat << EOF > /etc/apt/apt.conf.d/99-disable-periodic-update
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Download-Upgradeable-Packages "0";
APT::Periodic::AutocleanInterval "0";
APT::Periodic::Unattended-Upgrade "0";
EOF
gsettings set com.ubuntu.update-notifier no-show-notifications true || true

# B. Configure Epoptes Server
EPOPTES_FILE="/etc/default/epoptes-client"

if [ -f "$EPOPTES_FILE" ]; then
    if grep -q "^SERVER=$EPOPTES_SERVER" "$EPOPTES_FILE"; then
        echo ">>> Epoptes already configured correctly."
    else
        echo ">>> Configuring Epoptes to $EPOPTES_SERVER..."
        sed -i -E "s/^#?SERVER=.*/SERVER=$EPOPTES_SERVER/" "$EPOPTES_FILE"
        epoptes-client -c || echo "Warning: Epoptes cert fetch failed. Run 'epoptes-client -c' later."
    fi
else
    echo "Warning: Epoptes client config not found at $EPOPTES_FILE"
fi

# C. Set Timezone
timedatectl set-timezone Europe/Dublin

# D. SELF DESTRUCT
echo ">>> CONFIGURATION COMPLETE."
echo ">>> Deleting this script file to protect Wi-Fi passwords..."
rm -- "$0"
echo ">>> Script deleted. Please Reboot."
