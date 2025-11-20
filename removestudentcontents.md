#Create File
sudo nano /etc/systemd/system/cleanup-student.service

#File Contents
[Unit]
Description=Wipe Student AD Profile on Boot
# CRITICAL: Wait for Network and User Identity Services (SSSD)
# This ensures we don't try to delete a mount that isn't there yet.
After=network-online.target sssd.service systemd-user-sessions.service
Wants=network-online.target

[Service]
Type=oneshot
User=root

# Delete the ENTIRE folder. 
# When the student logs in, PAM will see the folder is missing 
# and generate a fresh one from /etc/skel.
ExecStart=/bin/bash -c 'if [ -d "/home/student@SEC.local" ]; then rm -rf /home/student@SEC.local; fi'

# Optional: Log to syslog so you can verify it ran
ExecStartPost=/usr/bin/logger "Systemd Cleanup: Wiped /home/student@SEC.local"

[Install]
WantedBy=multi-user.target



# 1. Reload systemd to read the new file
sudo systemctl daemon-reload

# 2. Enable it to run on every boot
sudo systemctl enable cleanup-student.service
