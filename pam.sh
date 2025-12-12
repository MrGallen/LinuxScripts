
#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# ==========================================
#     SCHOOL LINUX SYSTEM CONFIGURATION
#          (Ubuntu 24.04 LTS)
# ==========================================

# --- CONFIGURATION ---
# 1. ACCOUNTS
STUDENT_USER="student@SEC.local"
ADMIN_USER_1="secsuperuser"
ADMIN_USER_2="egallen@SEC.local"

# 3. GROUPS & SERVER
# Space-separated list of accounts.
MOCK_GROUP="mock@SEC.local lccs@SEC.local lccs1@SEC.local" 
EXAM_USER="exam@SEC.local"
TEST_USER="exam1@SEC.local"


# 1. ROOT CHECK
if [ "$(id -u)" -ne 0 ]; then
  echo ">>> Error: Must run as root."
  exit 1
fi

# 4. PAM MASTER CONTROLLER
echo ">>> Configuring PAM hooks..."

mkdir -p /usr/local/etc/chrome_policies
cat << EOF > /usr/local/etc/chrome_policies/student_policy.json
{
  "DefaultSearchProviderEnabled": true,
  "DefaultSearchProviderName": "Google",
  "DefaultSearchProviderSearchURL": "https://www.google.com/search?q={searchTerms}",
  "ShowFirstRunExperience": false,
  "PromotionalTabsEnabled": false,
  "BrowserSignin": 0,
  "DefaultBrowserSettingEnabled": false,
  "MetricsReportingEnabled": false,
  "SyncDisabled": true,
  "PasswordManagerEnabled": false
}
EOF

cat << EOF > /usr/local/bin/pam_hook.sh
#!/bin/bash
USER="\$PAM_USER"
TYPE="\$PAM_TYPE"

# --- USER DEFINITIONS ---
STUDENT="$STUDENT_USER"
EXAM="$EXAM_USER"
TEST="$TEST_USER"
NO_NET_USERS="$MOCK_GROUP $EXAM_USER $TEST_USER"

CHROME_MANAGED="/etc/opt/chrome/policies/managed"
POLICY_SOURCE="/usr/local/etc/chrome_policies/student_policy.json"
POLICY_DEST="\$CHROME_MANAGED/student_policy.json"
PDF_SOURCE="/opt/sec_exam_resources/Python_Reference.pdf"

# --- FUNCTIONS ---
block_internet() {
    # 1. ALLOW Loopback (Internal Apps)
    iptables -I OUTPUT 1 -o lo -j ACCEPT
    
    # 2. ALLOW Local Network (Epoptes needs this!)
    # Assuming school uses standard 192.168.x.x or 10.x.x.x
    # If uncertain, we allow all private ranges.
    iptables -I OUTPUT 2 -d 192.168.0.0/16 -j ACCEPT
    iptables -I OUTPUT 3 -d 10.0.0.0/8 -j ACCEPT
    iptables -I OUTPUT 4 -d 172.16.0.0/12 -j ACCEPT

    # 3. BLOCK Everything Else for this User
    # We use -I (Insert) to make sure this is at the TOP of the list
    iptables -I OUTPUT 5 -m owner --uid-owner "\$USER" -j REJECT
    
    # 4. BLOCK IPv6 as well (To be safe)
    ip6tables -I OUTPUT 1 -m owner --uid-owner "\$USER" -j REJECT
}

unblock_internet() {
    # Clean up the rules by User Owner match
    iptables -D OUTPUT -m owner --uid-owner "\$USER" -j REJECT || true
    ip6tables -D OUTPUT -m owner --uid-owner "\$USER" -j REJECT || true
    # Note: We leave the ALLOW rules as they are harmless generic allows
}

setup_exam_files() {
    sleep 2
    DESKTOP="/home/\$USER/Desktop"
    mkdir -p "\$DESKTOP"
    if [ -f "\$PDF_SOURCE" ]; then
        cp "\$PDF_SOURCE" "\$DESKTOP/"
        chown "\$USER":"\$USER" "\$DESKTOP/Python_Reference.pdf"
        chmod 444 "\$DESKTOP/Python_Reference.pdf" 
    fi
}

# --- LOGIN LOGIC ---
if [ "\$TYPE" == "open_session" ]; then
    if [ "\$USER" == "\$STUDENT" ]; then
        mkdir -p "\$CHROME_MANAGED"
        ln -sf "\$POLICY_SOURCE" "\$POLICY_DEST"
    else
        rm -f "\$POLICY_DEST"
    fi

    if [[ " \$NO_NET_USERS " =~ " \$USER " ]]; then
        block_internet
        logger "SEC_SCRIPT: Internet Blocked for \$USER"
    fi

    if [ "\$USER" == "\$EXAM" ] || [ "\$USER" == "\$TEST" ]; then
        setup_exam_files &
    fi
fi

# --- LOGOUT LOGIC ---
if [ "\$TYPE" == "close_session" ]; then
    /usr/local/bin/universal_cleanup.sh "\$USER" chrome

    if [[ " \$NO_NET_USERS " =~ " \$USER " ]]; then
        unblock_internet
    fi

    if [ "\$USER" == "\$STUDENT" ] || [ "\$USER" == "\$TEST" ]; then
        rm -f "\$POLICY_DEST"
        /usr/local/bin/universal_cleanup.sh "\$USER" wipe
    fi
fi
EOF
chmod +x /usr/local/bin/pam_hook.sh

if ! grep -q "pam_hook.sh" /etc/pam.d/common-session; then
    echo "session optional pam_exec.so /usr/local/bin/pam_hook.sh" >> /etc/pam.d/common-session
fi

# D. SELF DESTRUCT (Security)
echo ">>> CONFIGURATION COMPLETE."
echo ">>> Deleting this script file..."
rm -- "$0"
echo ">>> Script deleted. Please Reboot."
