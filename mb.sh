sudo apt purge zenity
#!/bin/bash

APP_DIR="/home/secsuperuser/.local/share/applications"
APP_ID="elclnfbbopfkicmhcihlblljgklhhagi"
FILENAME="chrome-$APP_ID-Default.desktop"
FULL_PATH="$APP_DIR/$FILENAME"

echo "Looking for: $FULL_PATH"

if [ -f "$FULL_PATH" ]; then
    echo "Attempting to remove shortcut: $FILENAME"
    rm "$FULL_PATH"
    if [ $? -eq 0 ]; then
        echo "Successfully removed $FILENAME."
    else
        echo "Error: Failed to remove $FILENAME."
    fi
else
    echo "Shortcut not found: $FULL_PATH. It may have already been removed."
fi


# Set variables for the udev rule file and device information
RULES_FILE="/etc/udev/rules.d/99-microbit.rules"
VENDOR_ID="0d28"
PRODUCT_ID="0204"

# Check if the script is run with root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root."
    exit 1
fi

# Check if the udev rule file already exists
if [ -f "$RULES_FILE" ]; then
    echo "The udev rule file already exists. Skipping creation."
else
    # Create the udev rule file
    echo "Creating udev rule file for micro:bit access..."
    echo "SUBSYSTEM==\"tty\", ATTRS{idVendor}==\"$VENDOR_ID\", ATTRS{idProduct}==\"$PRODUCT_ID\", MODE=\"0666\"" > "$RULES_FILE"
    echo "Udev rule file created at $RULES_FILE."
fi

# Reload udev rules
echo "Reloading udev rules..."
udevadm control --reload

# Print confirmation message
echo "Udev rules reloaded. The micro:bit should now be accessible to all users."
