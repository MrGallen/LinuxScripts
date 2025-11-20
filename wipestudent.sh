#sudo nano /usr/local/bin/wipe_student.sh

#!/bin/bash

# 1. Define the specific user to target
TARGET_USER="student@SEC.local"

# 2. Check if the user logging out matches the target
# PAM passes the username in the variable $PAM_USER
if [ "$PAM_USER" = "$TARGET_USER" ]; then

    # 3. Double check the directory exists to avoid errors
    if [ -d "/home/$TARGET_USER" ]; then
        
        # Optional: Kill any lingering processes by this user so files aren't locked
        pkill -u "$TARGET_USER"
        
        # 4. Wipe the directory
        # We remove the folder entirely. pam_mkhomedir usually recreates it on next login.
        # If you prefer to keep the folder and only empty it, change to: rm -rf /home/$TARGET_USER/*
        rm -rf "/home/$TARGET_USER"
        
        # Log the action (Optional, for troubleshooting)
        logger "PAM_EXEC: Wiped home directory for $TARGET_USER"
    fi
fi

#sudo chmod +x /usr/local/bin/wipe_student.sh

#Go too - sudo nano /etc/pam.d/common-session

#Add this to the end
#session optional pam_exec.so type=close_session /usr/local/bin/wipe_student.sh

