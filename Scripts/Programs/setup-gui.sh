#!/data/data/com.termux/files/usr/bin/bash
# setup-gui.sh - a tappable installer menu for the desktop.
#
# This picks what to INSTALL. It is not the same as play-gui.sh, which
# launches things already installed.
#
# Needs the desktop running. Without one, use the terminal menu instead:
#   bash setup.sh

set -eu

URL="https://raw.githubusercontent.com/Warlord19winter/Termux-Desktop-Srcripts/main/Scripts/Interactive%20Menu/setup-gui.sh"

echo "==> Installing yad"
pkg install -y yad

echo "==> Fetching setup-gui.sh"
curl -fL "$URL" -o "$HOME/setup-gui.sh"
chmod +x "$HOME/setup-gui.sh"

cat << 'EOF'

Installed.

  ~/setup-gui.sh    tappable menu for installing things
  bash setup.sh     the same thing in the terminal, no desktop needed

Start Termux:X11 and the desktop before running the GUI version.
EOF
