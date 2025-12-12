#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# 1. ROOT CHECK
if [ "$(id -u)" -ne 0 ]; then
  echo ">>> Error: Must run as root."
  exit 1
fi

# 2. UPDATES & PACKAGE MANAGEMENT
echo ">>> Preparing system..."
export DEBIAN_FRONTEND=noninteractive

# A. CLEANUP FIRST
echo ">>> Purging conflicting packages..."
snap remove thonny || true
apt-get purge -y "gnome-initial-setup" "gnome-tour" "aisleriot" "gnome-mahjongg" "gnome-mines" "gnome-sudoku" || true

# B. INSTALL SYSTEM LIBRARIES & APPS
echo ">>> Installing System & Python Libraries..."
apt-get update -q 
apt-get install -y -q \
    thonny \
    gnome-terminal \
    python3-pip \
    python3-tk \
    python3-numpy \
    python3-matplotlib \
    python3-pandas \
    python3-pygal \
    python3-pygame

# C. INSTALL CUSTOM PIP LIBRARIES
echo ">>> Installing Custom PyPI Libraries..."
pip3 install firebase compscifirebase --break-system-packages

# D. SYSTEM UPGRADE
echo ">>> Upgrading System..."
apt-get upgrade -y -q
apt-get autoremove -y -q

# E. INSTALL SNAPS
echo ">>> Installing Snaps..."
snap install --classic code || true
rm -f /usr/share/applications/code.desktop
rm -f /usr/share/applications/vscode.desktop
