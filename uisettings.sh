
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

# 3. GROUPS & SERVER
# Space-separated list of accounts.
MOCK_GROUP="mock@SEC.local lccs@SEC.local lccs1@SEC.local" 
EXAM_USER="exam@SEC.local"
TEST_USER="exam1@SEC.local"


# 1. ROOT CHECK
if [ "$(id -u)" -ne 0 ]; then
  echo ">>> Error: Must run as root."
  exit 1
fi

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
    # === STRICT EXAM MODE ===
    gsettings set org.gnome.desktop.interface gtk-theme 'Yaru'
    gsettings set org.gnome.desktop.interface icon-theme 'Yaru'
    
    # 1. DOCK: ONLY THONNY
    gsettings set org.gnome.shell favorite-apps "['$THONNY']"
    
    # 2. DISABLE "SUPER" KEY (Prevents opening App Menu)
    gsettings set org.gnome.mutter overlay-key ''
    gsettings set org.gnome.shell.keybindings toggle-overview "[]"

    gsettings set org.gnome.shell enable-hot-corners false
    gsettings set org.gnome.mutter edge-tiling true
    
    # 3. HIDE "SHOW APPLICATIONS" GRID BUTTON (9 Dots)
    # This prevents users from clicking the button to see other apps
    for schema in "org.gnome.shell.extensions.dash-to-dock" "org.gnome.shell.extensions.ubuntu-dock"; do
        gsettings set \$schema show-show-apps-button false
    done

    # 4. DISABLE RUN COMMAND
    gsettings set org.gnome.desktop.lockdown disable-command-line true
else
    # === STUDENT MODE ===
    # Reset Super Key & App Grid for normal students
    gsettings set org.gnome.mutter overlay-key 'Super_L'
    gsettings set org.gnome.shell.keybindings toggle-overview "['<Super>s']"
    
    gsettings set org.gnome.desktop.interface gtk-theme 'Yaru-purple'
    gsettings set org.gnome.desktop.interface icon-theme 'Yaru-purple'
    gsettings set org.gnome.shell favorite-apps "['google-chrome.desktop', 'firefox_firefox.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Terminal.desktop', '$CODE', '$THONNY']"

    gsettings set org.gnome.shell enable-hot-corners true
    gsettings set org.gnome.mutter edge-tiling true
    
    # Ensure Apps Button is VISIBLE for students
    for schema in "org.gnome.shell.extensions.dash-to-dock" "org.gnome.shell.extensions.ubuntu-dock"; do
        gsettings set \$schema show-show-apps-button true
    done
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


# D. SELF DESTRUCT (Security)
echo ">>> CONFIGURATION COMPLETE."
echo ">>> Deleting this script file..."
rm -- "$0"
echo ">>> Script deleted. Please Reboot."
