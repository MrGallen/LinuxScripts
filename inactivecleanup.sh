
#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# ==========================================
#     SCHOOL LINUX SYSTEM CONFIGURATION
#          (Ubuntu 24.04 LTS)
# ==========================================

INACTIVE_DAYS=120

# 1. ROOT CHECK
if [ "$(id -u)" -ne 0 ]; then
  echo ">>> Error: Must run as root."
  exit 1
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

# D. SELF DESTRUCT (Security)
echo ">>> CONFIGURATION COMPLETE."
echo ">>> Deleting this script file..."
rm -- "$0"
echo ">>> Script deleted. Please Reboot."
