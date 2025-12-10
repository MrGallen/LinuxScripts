#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# ==========================================
#      SCHOOL LINUX SYSTEM CONFIGURATION
# ==========================================

# --- CONFIGURATION ---
STUDENT_USER="student@SEC.local"
ADMIN_USER_1="secsuperuser"
ADMIN_USER_2="egallen@SEC.local"

# User Groups (Space-separated lists)
# Mock/LCCS: No Internet, Thonny Only, 7-Day Wipe
MOCK_GROUP="mock@SEC.local lccs@SEC.local lccs1@SEC.local" 

# Exam: No Internet, Thonny Only, 7-Day Wipe, PDF on Desktop
EXAM_USER="exam@SEC.local"

# Test: No Internet, Thonny Only, Immediate Wipe, PDF on Desktop
TEST_USER="exam1@SEC.local"

# Settings
INACTIVE_DAYS=120
# Direct link to the Python Reference PDF
PDF_URL="https://www.examinations.ie/archive/exampapers/2022/LC219ALP000EV.pdf" 
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
# Remove 'deb' versions to prevent duplicates
sudo apt purge "thonny*" "python3-thonny*" "code*" "gnome-initial-setup" "gnome-tour" -y || true

# Delete leftover shortcuts
sudo rm -f /usr/share/applications/thonny.desktop
sudo rm -f /usr/share/applications/org.thonny.Thonny.desktop
sudo rm -f /usr/share/applications/code.desktop
sudo rm -f /usr/share/applications/vscode.desktop

echo ">>> Installing Snaps..."
sudo snap install --classic code || true
sudo snap install thonny || true

# 2b. PREPARE EXAM RESOURCES
echo ">>> Downloading Exam Resources..."
mkdir -p /opt/sec_exam_resources
# Download the Python Reference sheet once as root
wget -q -O /opt/sec_exam_resources/Python_Reference.pdf "$PDF_URL" || echo "Warning: PDF Download failed. Check URL."
chmod 644 /opt/sec_exam_resources/Python_Reference.pdf

# 3. UNIVERSAL CLEANUP LOGIC (Supports Immediate & 7-Day Wipes)
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

# Wipes folder ONLY if it hasn't been modified in 7 days
wipe_if_older_than_7_days() {
    if [ -d "/home/\$TARGET_USER" ]; then
        # Check if the home folder modification time is older than 7 days
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

# Create a Daily Cron Job to check the 7-day accounts
echo "#!/bin/bash" > /etc/cron.daily/sec_cleanup
for user in $MOCK_GROUP $EXAM_USER; do
    echo "/usr/local/bin/universal_cleanup.sh $user check_7day" >> /etc/cron.daily/sec_cleanup
done
chmod +x /etc/cron.daily/sec_cleanup

# 4. PAM MASTER CONTROLLER (Policies, Internet, Wipes, PDF)
echo ">>> Configuring PAM hooks..."

# A. Create Chrome Policy (Student Only)
mkdir -p /usr/local/etc/chrome_policies
cat << EOF > /usr/local/etc/chrome_policies/student_policy.json
{
  "DefaultSearchProviderEnabled": true,
  "DefaultSearchProviderName": "Google",
  "DefaultSearchProviderSearchURL": "https://www.google.com/search?q={searchTerms}",
  "ShowFirstRunExperience": false,
  "PromotionalTabsEnabled": false,
  "BrowserSignin": 0
}
EOF

# B. Create the Hook Script
cat << EOF > /usr/local/bin/pam_hook.sh
#!/bin/bash
USER="\$PAM_USER"
TYPE="\$PAM_TYPE"

# --- USER DEFINITIONS ---
STUDENT="$STUDENT_USER"
EXAM="$EXAM_USER"
TEST="$TEST_USER"
# Combine Mock/Exam/Test into a "No Internet" list
NO_NET_USERS="$MOCK_GROUP $EXAM_USER $TEST_USER"

CHROME_MANAGED="/etc/opt/chrome/policies/managed"
POLICY_SOURCE="/usr/local/etc/chrome_policies/student_policy.json"
POLICY_DEST="\$CHROME_MANAGED/student_policy.json"
PDF_SOURCE="/opt/sec_exam_resources/Python_Reference.pdf"

# --- FUNCTIONS ---

block_internet() {
    # Block network for this specific user ID
    # Allow Loopback (Localhost) so Apps don't crash
    iptables -A OUTPUT -o lo -j ACCEPT
    iptables -A OUTPUT -m owner --uid-owner "\$USER" -j REJECT
}

unblock_internet() {
    # Remove the specific rule for this user
    iptables -D OUTPUT -m owner --uid-owner "\$USER" -j REJECT || true
    iptables -D OUTPUT -o lo -j ACCEPT || true
}

setup_exam_files() {
    # Wait a moment for home dir creation
    sleep 2
    DESKTOP="/home/\$USER/Desktop"
    mkdir -p "\$DESKTOP"
    if [ -f "\$PDF_SOURCE" ]; then
        cp "\$PDF_SOURCE" "\$DESKTOP/"
        chown "\$USER":"\$USER" "\$DESKTOP/Python_Reference.pdf"
        chmod 444 "\$DESKTOP/Python_Reference.pdf" # Read-only
    fi
}

# --- LOGIN LOGIC ---
if [ "\$TYPE" == "open_session" ]; then
    
    # 1. STUDENT
    if [ "\$USER" == "\$STUDENT" ]; then
        mkdir -p "\$CHROME_MANAGED"
        ln -sf "\$POLICY_SOURCE" "\$POLICY_DEST"
        logger "SEC_SCRIPT: Applied Chrome Policy for \$USER"  # <--- NEW LOG
    else
        rm -f "\$POLICY_DEST"
    fi

    # 2. NO INTERNET
    if [[ " \$NO_NET_USERS " =~ " \$USER " ]]; then
        block_internet
        logger "SEC_SCRIPT: Blocked Internet for \$USER"      # <--- NEW LOG
    fi

    # 3. EXAM FILES
    if [ "\$USER" == "\$EXAM" ] || [ "\$USER" == "\$TEST" ]; then
        setup_exam_files &
        logger "SEC_SCRIPT: Deployed Exam PDF for \$USER"     # <--- NEW LOG
    fi
fi

# --- LOGOUT LOGIC ---
if [ "\$TYPE" == "close_session" ]; then
    
    # 1. Clean Chrome Locks (Everyone)
    /usr/local/bin/universal_cleanup.sh "\$USER" chrome

    # 2. Unblock Internet (Clean up iptables)
    if [[ " \$NO_NET_USERS " =~ " \$USER " ]]; then
        unblock_internet
    fi

    # 3. IMMEDIATE WIPE (Student & Test ONLY)
    if [ "\$USER" == "\$STUDENT" ] || [ "\$USER" == "\$TEST" ]; then
        rm -f "\$POLICY_DEST"
        /usr/local/bin/universal_cleanup.sh "\$USER" wipe
    fi
    
    # Note: Mock & Exam are NOT wiped here. They wait for the 7-day Cron job.
fi
EOF
chmod +x /usr/local/bin/pam_hook.sh

# C. Register PAM
if ! grep -q "pam_hook.sh" /etc/pam.d/common-session; then
    echo "session optional pam_exec.so /usr/local/bin/pam_hook.sh" >> /etc/pam.d/common-session
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
# Clean Stale Epoptes PID
ExecStart=/bin/bash -c 'rm -f /var/run/epoptes-client.pid'
ExecStartPost=/usr/bin/logger "Systemd: Boot cleanup complete"

[Install]
WantedBy=multi-user.target
EOF
chmod 644 /etc/systemd/system/cleanup-boot.service
systemctl daemon-reload
systemctl enable --now cleanup-boot.service

# 6. UI ENFORCEMENT (Themes, Restrictions, Icons)
echo ">>> generating UI Enforcer script..."

if [ -f "/var/lib/snapd/desktop/applications/code_code.desktop" ]; then CODE="code_code.desktop"; else CODE="code.desktop"; fi
if [ -f "/var/lib/snapd/desktop/applications/thonny_thonny.desktop" ]; then THONNY="thonny_thonny.desktop"; else THONNY="thonny.desktop"; fi

cat << EOF > /usr/local/bin/force_ui.sh
#!/bin/bash

# --- 1. ADMIN PROTECTION ---
if [ "\$USER" == "$ADMIN_USER_1" ] || [ "\$USER" == "$ADMIN_USER_2" ]; then
    exit 0
fi

# --- 2. DEFINE GROUPS ---
RESTRICTED_USERS="$MOCK_GROUP $EXAM_USER $TEST_USER"

sleep 3

# --- 3. COMMON SETTINGS ---
# Mute Audio
pactl set-sink-mute @DEFAULT_SINK@ 1 > /dev/null 2>&1 || true
# No Sleep / Performance
powerprofilesctl set performance || true
gsettings set org.gnome.desktop.screensaver lock-enabled false
gsettings set org.gnome.desktop.session idle-delay 0
# Block Printing
gsettings set org.gnome.desktop.lockdown disable-printing true
gsettings set org.gnome.desktop.lockdown disable-print-setup true

# --- 4. CONDITIONAL UI ---

if [[ " \$RESTRICTED_USERS " =~ " \$USER " ]]; then
    # === RESTRICTED MODE (Mock/Exam/Test) ===
    
    # Visuals: Default Blue/Orange
    gsettings set org.gnome.desktop.interface gtk-theme 'Yaru'
    gsettings set org.gnome.desktop.interface icon-theme 'Yaru'
    gsettings set org.gnome.desktop.interface color-scheme 'default'

    # Dock: THONNY + FILES ONLY
    gsettings set org.gnome.shell favorite-apps "['org.gnome.Nautilus.desktop', '$THONNY']"
    
    # Extra Lockdown: Disable Command Prompt (Alt+F2)
    gsettings set org.gnome.desktop.lockdown disable-command-line true
    
else
    # === STUDENT MODE ===
    
    # Visuals: Purple (Force Yaru-purple theme)
    gsettings set org.gnome.desktop.interface gtk-theme 'Yaru-purple'
    gsettings set org.gnome.desktop.interface icon-theme 'Yaru-purple'
    gsettings set org.gnome.desktop.interface color-scheme 'default'
    
    # Dock: Chrome + Code + Thonny + Files
    gsettings set org.gnome.shell favorite-apps "['google-chrome.desktop', 'firefox_firefox.desktop', 'org.gnome.Nautilus.desktop', '$CODE', '$THONNY']"
fi

# --- 5. DOCK STYLE (Bottom) ---
for schema in "org.gnome.shell.extensions.dash-to-dock" "org.gnome.shell.extensions.ubuntu-dock"; do
    gsettings set \$schema dock-position 'BOTTOM'
    gsettings set \$schema autohide true
    gsettings set \$schema extend-height false
    gsettings set \$schema dash-max-icon-size 54
    gsettings set \$schema dock-fixed false
done

# --- 6. CLEANUP ---
gsettings set org.gnome.shell welcome-dialog-last-shown-version '999999'
EOF

chmod +x /usr/local/bin/force_ui.sh

# Create Autostart Entry
cat << EOF > /etc/xdg/autostart/force_ui.desktop
[Desktop Entry]
Type=Application
Name=Force UI
Exec=/usr/local/bin/force_ui.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

# 7. INACTIVE USER CLEANUP (Maintenance)
cat << EOF > /usr/local/bin/cleanup_old_users.sh
#!/bin/bash
set -euo pipefail

# Define threshold for system UIDs (usually 1000 on standard Linux distros)
UID_MIN=1000

lastlog -b "$INACTIVE_DAYS" | awk 'NR>1 {print \$1}' | while read -r U; do
    
    # 1. Skip if user is empty
    [[ -z "\$U" ]] && continue

    # 2. Safety Check: Get UID to ensure we don't delete system services
    USER_UID=\$(id -u "\$U" 2>/dev/null || echo 0)
    
    # 3. Exclusions: Root, Admins, or System Accounts
    if [[ "\$USER_UID" -lt "\$UID_MIN" || "\$U" == "root" || "\$U" == "$ADMIN_USER_1" || "\$U" == "$ADMIN_USER_2" ]]; then
        continue
    fi

    # 4. Perform Cleanup
    logger "Inactive Cleanup: Removing account for \$U"
    
    # Kill processes
    pkill -u "\$U" || true
    
    # Delete the user AND their home directory/mail spool
    # -r removes the home directory and mail spool
    # -f forces removal even if user is logged in (redundant with pkill but safer)
    userdel -r -f "\$U"

    logger "Inactive Cleanup: User \$U deleted successfully."
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

# Disable Fast User Switching (Prevents logic conflicts)
cat << EOF > /etc/dconf/profile/user
user-db:user
system-db:local
EOF

mkdir -p /etc/dconf/db/local.d
cat << EOF > /etc/dconf/db/local.d/00-disable-switching
[org/gnome/desktop/lockdown]
disable-user-switching=true
EOF
dconf update

# Hide VNC & Terminal Icons
APPS=("x11vnc.desktop" "xtigervncviewer.desktop" "debian-xterm.desktop" "debian-uxterm.desktop")
for app in "${APPS[@]}"; do
    FILE="/usr/share/applications/$app"
    [ -f "$FILE" ] && echo "NoDisplay=true" >> "$FILE"
done

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
    sed -i '/\[Default Applications\]/a text/plain=code_code.desktop' "$
