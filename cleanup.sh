#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# 1. ACCOUNTS
STUDENT_USER="student@SEC.local"
ADMIN_USER_1="secsuperuser"
ADMIN_USER_2="egallen@SEC.local"

# 3. GROUPS & SERVER
# Space-separated list of accounts.
MOCK_GROUP="mock@SEC.local lccs@SEC.local lccs1@SEC.local" 
EXAM_USER="exam@SEC.local"
TEST_USER="exam1@SEC.local"
EPOPTES_SERVER="epoptes.server.local"

# 1. ROOT CHECK
if [ "$(id -u)" -ne 0 ]; then
  echo ">>> Error: Must run as root."
  exit 1
fi

# 3. UNIVERSAL CLEANUP LOGIC
cat << EOF > /usr/local/bin/universal_cleanup.sh
#!/bin/bash
TARGET_USER="\$1"
ACTION="\$2" 

clean_chrome() {
    CHROME_DIR="/home/\$TARGET_USER/.config/google-chrome"
    if [ -d "\$CHROME_DIR" ]; then
        rm -f "\$CHROME_DIR/SingletonLock" "\$CHROME_DIR/SingletonSocket" "\$CHROME_DIR/SingletonCookie"
    fi
}

wipe_immediate() {
    if [ -d "/home/\$TARGET_USER" ]; then
        pkill -u "\$TARGET_USER" || true
        sleep 1
        rm -rf "/home/\$TARGET_USER"
        logger "CLEANUP: Immediate wipe for \$TARGET_USER"
    fi
}

wipe_if_older_than_7_days() {
    if [ -d "/home/\$TARGET_USER" ]; then
        if [ \$(find "/home/\$TARGET_USER" -maxdepth 0 -mtime +7) ]; then
            pkill -u "\$TARGET_USER" || true
            rm -rf "/home/\$TARGET_USER"
            logger "CLEANUP: 7-Day limit reached. Wiped \$TARGET_USER"
        fi
    fi
}

if [ "\$ACTION" == "chrome" ]; then clean_chrome; fi
if [ "\$ACTION" == "wipe" ]; then wipe_immediate; fi
if [ "\$ACTION" == "check_7day" ]; then wipe_if_older_than_7_days; fi

rm -f /home/*/.local/share/applications/*mmfbcljfglokjkanfeinibellchtcxn*
EOF
chmod +x /usr/local/bin/universal_cleanup.sh

# Cron for 7-day cleanup
echo "#!/bin/bash" > /etc/cron.daily/sec_cleanup
for user in $MOCK_GROUP $EXAM_USER; do
    echo "/usr/local/bin/universal_cleanup.sh $user check_7day" >> /etc/cron.daily/sec_cleanup
done
chmod +x /etc/cron.daily/sec_cleanup

  # D. SELF DESTRUCT (Security)
echo ">>> CONFIGURATION COMPLETE."
echo ">>> Deleting this script file..."
rm -- "$0"
echo ">>> Script deleted. Please Reboot."
