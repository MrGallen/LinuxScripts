#!/bin/bash

# Script to force Xorg (X11) as the default session in Ubuntu 24.04 (GDM)

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo "⚠️ Please run this script with sudo: sudo ./force_xorg.sh"
  exit 1
fi

GDM_CONF="/etc/gdm3/custom.conf"

echo "Attempting to set Xorg as the default display server in GDM..."

# 1. Ensure the [daemon] section exists
if ! grep -q '\[daemon\]' "$GDM_CONF"; then
    echo -e "\n[daemon]" >> "$GDM_CONF"
    echo "Added [daemon] section."
fi

# 2. Disable Wayland by setting WaylandEnable=false
# Use sed to replace the line if it exists, or append it if it doesn't
sed -i '/WaylandEnable/d' "$GDM_CONF"
sed -i '/\[daemon\]/aWaylandEnable=false' "$GDM_CONF"
echo "Set WaylandEnable=false."

# 3. Set the default session to Ubuntu on Xorg
# Use sed to replace the line if it exists, or append it
sed -i '/DefaultSession/d' "$GDM_CONF"
sed -i '/WaylandEnable=false/aDefaultSession=ubuntu-xorg.desktop' "$GDM_CONF"
echo "Set DefaultSession=ubuntu-xorg.desktop."

echo ""
echo "Configuration complete. Changes saved to $GDM_CONF."
echo "You must reboot the system for the change to take effect on the login screen."
echo ""

# Optional: Prompt to reboot immediately
read -r -p "Do you want to reboot now? (y/N): " response
case "$response" in
    [yY][eE][sS]|[yY])
        echo "Rebooting now..."
        reboot
        ;;
    *)
        echo "Please reboot manually (sudo reboot) to activate Xorg as the default."
        ;;
esac
