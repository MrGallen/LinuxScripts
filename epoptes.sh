#!/bin/bash
GDM_CONF="/etc/gdm3/custom.conf"
sed -i '/WaylandEnable/d' "$GDM_CONF"
sed -i '/\[daemon\]/aWaylandEnable=false' "$GDM_CONF"
echo "Set WaylandEnable=false."

# Get the current hostname and set the new hostname
# Get the current hostname
current_hostname=$(hostname)

# Check if the hostname already includes '.sec.local'
if [[ "$current_hostname" == *.SEC.local ]]; then
  echo "The hostname already includes '.sec.local'. No changes needed."
else
  # Append '.sec.local' to the current hostname
  new_hostname="${current_hostname}.SEC.local"
  echo "Setting new hostname to: $new_hostname"
  
  # Set the new hostname
  sudo hostnamectl set-hostname "$new_hostname"
  echo "Hostname updated successfully!"
fi

# Remove Veyon package
sudo apt purge -y veyon

# Install epoptes-client
sudo apt update
sudo apt install -y epoptes-client

# Automatically configure epoptes-client
echo "SERVER=epoptes-server.local" | sudo tee -a /etc/default/epoptes-client

# Run epoptes-client
sudo epoptes-client -c

# Update system and clean up
sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y

# Reboot once after all changes
sudo reboot

