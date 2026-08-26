#!/data/data/com.termux/files/usr/bin/bash
# play.sh - a menu for launching whatever games and emulators you have
# installed, plus play-gui.sh, a tappable version for the desktop.
#
# play.sh finds anything with an executable run.sh under ~/games/*/ so it
# picks up new installs on its own.

set -eu

BASE="https://raw.githubusercontent.com/Warlord19winter/Termux-Desktop-Srcripts/main/Scripts/Launchers"

echo "==> Installing yad (for the GUI picker)"
pkg install -y yad

echo "==> Fetching play.sh"
curl -fL "$BASE/play.sh" -o "$HOME/play.sh"
chmod +x "$HOME/play.sh"

echo "==> Fetching play-gui.sh"
curl -fL "$BASE/play-gui.sh" -o "$HOME/play-gui.sh"
chmod +x "$HOME/play-gui.sh"

mkdir -p "$HOME/games"

cat << 'EOF'

Installed.

  ~/play.sh              menu in the terminal
  ~/play.sh --list       just show what is installed
  ~/play.sh <name>       launch something directly
  ~/play.sh --x11 <name> start Termux:X11 with that game as the session
  ~/play-gui.sh          tappable picker (needs the desktop running)
EOF
