APPS=("x11vnc.desktop" "xtigervncviewer.desktop" "debian-xterm.desktop" "debian-uxterm.desktop")
for app in "${APPS[@]}"
do
    echo "NoDisplay=true" >> "/usr/share/applications/$app"
done
