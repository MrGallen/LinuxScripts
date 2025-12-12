#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# 1. ROOT CHECK
if [ "$(id -u)" -ne 0 ]; then
  echo ">>> Error: Must run as root."
  exit 1
fi

# 6. SYSTEMD BOOT CLEANUP (SAFETY NET)
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


# D. SELF DESTRUCT (Security)
echo ">>> CONFIGURATION COMPLETE."
echo ">>> Deleting this script file..."
rm -- "$0"
echo ">>> Script deleted. Please Reboot."
