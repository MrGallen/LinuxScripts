#Create File for 120 days inactivity clean up
sudo nano /usr/local/bin/cleanup_old_users.sh

#File Contents
#!/bin/bash

# CONFIGURATION
DAYS=120
DOMAIN_SUFFIX="@SEC.local" # Strict filter to protect other admins

# 1. Get list of users inactive for >120 days
# lastlog -b 120 shows users older than 120 days
# grep filters for only your domain users
# awk grabs the first column (username)
lastlog -b $DAYS | grep "$DOMAIN_SUFFIX" | awk '{print $1}' | while read -r USER_ACCOUNT; do

    # Define home path
    HOME_DIR="/home/$USER_ACCOUNT"

    # 2. Safety Check: Ensure directory exists
    if [ -d "$HOME_DIR" ]; then
        echo "Processing $USER_ACCOUNT..."

        # 3. Kill lingering processes for this user
        pkill -u "$USER_ACCOUNT" || true

        # 4. Wipe the profile directory
        rm -rf "$HOME_DIR"

        # 5. Log the action to system journals
        logger "Inactive Cleanup: Wiped profile for $USER_ACCOUNT (Inactive > $DAYS days)"
    fi
done

#Make Executable
sudo chmod +x /usr/local/bin/cleanup_old_users.sh

#Make service file to run it
sudo nano /etc/systemd/system/delete-inactive-users.service

#File Contents
[Unit]
Description=Cleanup Inactive Student Profiles (>120 Days)
# Ensure authentication services are up before we try reading lastlog/users
After=network-online.target sssd.service systemd-user-sessions.service

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/bin/cleanup_old_users.sh

#Create Timer File
sudo nano /etc/systemd/system/delete-inactive-users.timer

#Timer file contents
[Unit]
Description=Cleanup Inactive Student Profiles (>120 Days)
# Ensure authentication services are up before we try reading lastlog/users
After=network-online.target sssd.service systemd-user-sessions.service

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/bin/cleanup_old_users.sh

