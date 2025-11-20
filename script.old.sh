#!/bin/bash

# ==============================================================================
# Ubuntu 25.04 School Configuration Script
#
# This script automates the setup of a student-ready Ubuntu machine.
# It handles:
#   - Software installation (Thonny, VSCode, Chrome, etc.)
#   - User policies (admin rights, inactive account deletion)
#   - System lockdowns (disabling settings for standard users)
#   - Desktop customization (wallpaper, dock, theme)
#   - Scheduled tasks (daily shutdown)
#
# USAGE:
# 1. Place your school photo named 'school-photo.jpg' in the same directory.
# 2. Run with sudo: sudo ./setup_school_pc.sh
# ==============================================================================

# --- Script Setup ---
# Exit immediately if a command exits with a non-zero status.
set -e

# --- 1. System Preparation & Updates ---
echo "🔄 Updating system packages..."
apt-get update
apt-get upgrade -y
apt-get install -y wget gpg apt-transport-https curl snapd unattended-upgrades python3-pip git

# --- 2. Software Installation ---
echo "💻 Installing required software..."

# Install from APT repository
apt-get install -y thonny libreoffice-writer libreoffice-calc libreoffice-draw libreoffice-gtk3 fonts-dejavu


# Install Google Chrome
echo "🌐 Installing Google Chrome..."
wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/google-chrome-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome-keyring.gpg] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list
apt-get update
apt-get install -y google-chrome-stable

# Install VS Code
echo "📝 Installing Visual Studio Code..."
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /etc/apt/trusted.gpg.d/microsoft.gpg
echo "deb [arch=amd64] https://packages.microsoft.com/repos/vscode stable main" > /etc/apt/sources.list.d/vscode.list
apt-get update
apt-get install -y code

# Install from Snap Store
snap install notepad-plus-plus

# Script to delete inactive users
echo "🗑️ Creating script to remove users inactive for 120 days..."
cat > /usr/local/bin/delete_inactive_users.sh << 'EOF'
#!/bin/bash
INACTIVE_DAYS=120
# Get list of users not logged in for 120 days, excluding system/admin users
INACTIVE_USERS=$(lastlog -b $INACTIVE_DAYS | awk '
  NR>1 && $3 != "**Never" && $1 != "root" && $1 != "secsuperuser" && $1 != "egallen" {
    uid=$(id -u $1);
    if (uid >= 1000) print $1;
  }
')

if [ -n "$INACTIVE_USERS" ]; then
  for user in $INACTIVE_USERS; do
    echo "User '$user' has been inactive for over $INACTIVE_DAYS days. Deleting."
    userdel -r "$user"
  done
else
  echo "No inactive users to delete."
fi
EOF
chmod +x /usr/local/bin/delete_inactive_users.sh

# --- 4. System & Desktop Customization ---
echo "🎨 Customizing desktop environment..."


# Create a dconf profile to enforce system-wide settings
cat > /etc/dconf/profile/user << EOF
user-db:user
system-db:local
EOF

# Create the dconf database directory for system-wide settings
mkdir -p /etc/dconf/db/local.d/

# GSettings Overrides for all users
[org/gnome/desktop/interface]
accent-color='#008080'
clock-format='12h'
gtk-theme='Yaru-dark'

[org.gnome/desktop/session]
idle-delay=uint32 1800

[org.gnome.shell]
favorite-apps=['google-chrome.desktop', 'code.desktop', 'thonny.desktop']

[org.gnome.shell.extensions.dash-to-dock]
dock-position='LEFT'
dash-max-icon-size=56
dock-fixed=false
autohide=true

[org.gnome.mutter]
edge-tiling=true

[org.gnome.desktop.sound]
event-sounds=false
EOF

# Mute audio on login for all users
# We create a desktop file that runs at startup to mute the volume
mkdir -p /etc/xdg/autostart/
cat > /etc/xdg/autostart/mute-on-login.desktop << EOF
[Desktop Entry]
Type=Application
Name=Mute on Login
Exec=amixer -D pulse sset Master mute
Terminal=false
Hidden=true
EOF


# Lock key settings so users cannot change them
mkdir -p /etc/dconf/db/local.d/locks/
cat > /etc/dconf/db/local.d/locks/00-school-locks << EOF
# Lock the desktop and screensaver background
/org/gnome/desktop/background/picture-uri
/org/gnome/desktop/background/picture-uri-dark
/org/gnome/desktop/screensaver/picture-uri

# Lock accent color and theme
/org/gnome/desktop/interface/accent-color
/org/gnome/desktop/interface/gtk-theme
EOF

# Update dconf to apply all changes
dconf update

# Set System-wide settings
echo "⚙️ Applying system-wide settings..."
# Set timezone to Dublin
timedatectl set-timezone Europe/Dublin
# Set keyboard to UK layout
#localectl set-x11-keymap gb
# Set power profile to performance
powerprofilesctl set performance

# --- 5. Automation & Scheduled Tasks ---
echo "⏲️ Setting up automated tasks..."

# Configure automatic security updates
cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

# Setup daily cron jobs for root user
# Use a temporary file to avoid clobbering existing cron jobs
crontab -l > /tmp/current_cron || true
# Add shutdown task for 4:15 PM every day
echo "15 16 * * * /sbin/shutdown -h now" >> /tmp/current_cron
# Add inactive user check for 2:00 AM every day
echo "0 2 * * * /usr/local/bin/delete_inactive_users.sh" >> /tmp/current_cron
# Install the new cron file
crontab /tmp/current_cron
rm /tmp/current_cron

# --- 6. Final Cleanup ---
echo "🧹 Cleaning up..."
apt-get autoremove -y
apt-get clean

echo "✅✅✅ All tasks completed! ✅✅✅"
echo "A system reboot is recommended to ensure all settings are applied."

exit 0
