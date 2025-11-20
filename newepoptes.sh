#!/bin/bash
# =============================================
# Ubuntu 24.04 Epoptes Setup + Force Xorg Script
# =============================================

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo "⚠️ Please run this script with sudo: sudo ./epoptes_setup_xorg.sh"
  exit 1
fi

GDM_CONF="/etc/gdm3/custom.conf"

echo "-------------------------------------------"
echo "🔧 Configuring GDM to use Xorg (X11)..."
echo "-------------------------------------------"

# 1. Ensure [daemon] section exists
if ! grep -q '\[daemon\]' "$GDM_CONF"; then
    echo -e "\n[daemon]" >> "$GDM_CONF"
    echo "Added [daemon] section."
fi

# 2. Disable Wayland
sed -i '/WaylandEnable/d' "$GDM_CONF"
sed -i '/\[daemon\]/aWaylandEnable=false' "$GDM_CONF"
echo "Set WaylandEnable=false."

# 3. Set default session to Xorg
sed -i '/DefaultSession/d' "$GDM_CONF"
sed -i '/WaylandEnable=false/aDefaultSession=ubuntu-xorg.desktop' "$GDM_CONF"
echo "Set DefaultSession=ubuntu-xorg.desktop."

echo ""
echo "✅ GDM configuration complete. Xorg will be used after reboot."
echo ""

# -------------------------------------------
# Hostname Configuration
# -------------------------------------------

echo "-------------------------------------------"
echo "🖥️  Checking and updating hostname..."
echo "-------------------------------------------"

current_hostname=$(hostname)

if [[ "$current_hostname" == *.SEC.local ]]; then
  echo "The hostname already includes '.SEC.local'. No changes needed."
else
  new_hostname="${current_hostname}.SEC.local"
  echo "Setting new hostname to: $new_hostname"
  hostnamectl set-hostname "$new_hostname"
  echo "Hostname updated successfully!"
fi

# -------------------------------------------
# Epoptes Setup
# -------------------------------------------

echo "-------------------------------------------"
echo "📦 Setting up Epoptes client..."
echo "-------------------------------------------"

# Remove conflicting software (e.g., Veyon)
apt purge -y veyon

# Install Epoptes client
apt update
apt install -y epoptes-client

# Configure Epoptes client
echo "SERVER=epoptes-server.local" | tee -a /etc/default/epoptes-client
epoptes-client -c

# -------------------------------------------
# System Update & Cleanup
# -------------------------------------------

echo "-------------------------------------------"
echo "🔄 Updating and cleaning system..."
echo "-------------------------------------------"
apt update && apt upgrade -y && apt autoremove -y

# -------------------------------------------
# Final Step: Reboot
# -------------------------------------------

echo ""
echo "✅ All tasks complete: Xorg configured, hostname set, Epoptes installed."
echo "The system must reboot for all changes to take effect."
echo ""

read -r -p "Do you want to reboot now? (y/N): " response
case "$response" in
    [yY][eE][sS]|[yY])
        echo "Rebooting now..."
        reboot
        ;;
    *)
        echo "Please reboot manually later using: sudo reboot"
        ;;
esac

