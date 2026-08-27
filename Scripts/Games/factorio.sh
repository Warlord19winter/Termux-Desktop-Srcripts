#!/data/data/com.termux/files/usr/bin/bash
# Factorio (GOG Linux build)
#
# You supply the GOG installer yourself - this script extracts it and sets
# up the launcher. Buy Factorio on GOG, download the Linux installer on a
# desktop, and copy the .sh file onto your phone.
#
# Factorio is a native x86_64 binary, so it runs under box64 with the glibc
# bridge. Rendering goes through the Turnip Vulkan driver directly.
#
# TU_DEBUG=noconform tells Turnip to skip conformance checks it would
# otherwise fail; without it you get validation errors instead of a game.

set -eu

DEST="$HOME/games/factorio"
INSTALLER="${1:-}"

if [ -z "$INSTALLER" ] || [ ! -f "$INSTALLER" ]; then
    cat << 'USAGE'
Usage: factorio.sh /path/to/factorio_installer.sh

You need the GOG Linux installer for Factorio. Download it from your GOG
library on a desktop and copy the .sh file across.

If you launched this from the menu, run it directly instead:
  bash ~/.cache/termux-desktop/factorio.sh ~/storage/downloads/factorio_*.sh
USAGE
    exit 1
fi

echo "==> Installing dependencies"
pkg install -y glibc-runner box64-glibc unzip pulseaudio
pkg install -y mesa-vulkan-icd-freedreno vulkan-loader

echo "==> Extracting the GOG installer"
mkdir -p "$DEST/game"
unzip -o "$INSTALLER" -d "$DEST/game" || true

BIN="$DEST/game/data/noarch/game/bin/x64/factorio"
[ -f "$BIN" ] || { echo "Could not find the Factorio binary after extracting."; exit 1; }
chmod +x "$BIN"

echo "==> Writing launcher"
cat > "$DEST/run.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Factorio - x86_64 under box64, rendering through Turnip.
G="/data/data/com.termux/files/usr/glibc"

glibc-runner --shell "pulseaudio-start >/dev/null 2>&1; \
export DISPLAY=:0; \
export VK_ICD_FILENAMES=$G/share/vulkan/icd.d/freedreno_icd.aarch64.json; \
export TU_DEBUG=noconform; \
export SDL_AUDIODRIVER=pulseaudio; \
export PULSE_SERVER=127.0.0.1; \
box64 '$HOME/games/factorio/game/data/noarch/game/bin/x64/factorio'"
EOF
chmod +x "$DEST/run.sh"

cat << 'EOF'

Factorio installed to ~/games/factorio

Start Termux:X11, then run:
  ~/games/factorio/run.sh
EOF
