#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# 1. ROOT CHECK
if [ "$(id -u)" -ne 0 ]; then
  echo ">>> Error: Must run as root."
  exit 1
fi

#. PRIVACY LOCKDOWN
echo ">>> Locking down User Privacy..."

# 1. Configure default permission for NEW users (UMASK 077 = 700 permissions)
sed -i 's/^UMASK.*/UMASK 077/g' /etc/login.defs
sed -i 's/^#*DIR_MODE.*/DIR_MODE=0700/g' /etc/adduser.conf

# 2. Configure PAM to use strict umask if it creates home dirs
if grep -q "pam_mkhomedir.so" /etc/pam.d/common-session; then
    sed -i 's/pam_mkhomedir.so.*/pam_mkhomedir.so skel=\/etc\/skel\/ umask=0077/' /etc/pam.d/common-session
fi

# 3. Force permission fix on ALL CURRENT existing home directories
# This ensures student A cannot see student B's files right now.
echo ">>> Applying strict permissions to existing home folders..."
chmod 700 /home/*

# D. SELF DESTRUCT
echo ">>> CONFIGURATION COMPLETE."
echo ">>> Deleting this script file to protect Wi-Fi passwords..."
rm -- "$0"
echo ">>> Script deleted. Please Reboot."
