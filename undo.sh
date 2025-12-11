#!/bin/bash
set -e

# 1. ROOT CHECK
if [ "$(id -u)" -ne 0 ]; then
  echo ">>> Error: Must run as root."
  exit 1
fi

echo ">>> Removing PolicyKit restrictions..."

# 2. REMOVE THE RULE FILE
FILE="/etc/polkit-1/rules.d/99-school-restrictions.rules"

if [ -f "$FILE" ]; then
    rm -f "$FILE"
    echo ">>> File deleted: $FILE"
else
    echo ">>> File not found (already deleted)."
fi

# 3. RESTART POLKIT SERVICE
# This ensures the system stops using the old rule immediately
echo ">>> Restarting PolicyKit service..."
systemctl restart polkit

echo ">>> Done. Admin password is no longer forced for these actions."
