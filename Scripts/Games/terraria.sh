#!/data/data/com.termux/files/usr/bin/bash
# Terraria (GOG Linux build)
#
# Usage: terraria.sh /path/to/terraria_installer.sh
#
# Terraria is a .NET game, so Mono runs the managed code directly - no
# box64 needed. The native pieces it depends on (FNA3D, SDL2, FAudio) come
# from the installer and are already ARM-compatible in recent builds.
#
# If it fails with "Could not load file or assembly 'FNA'", the extraction
# was incomplete rather than anything being wrong with Mono - check that
# FNA.dll and mscorlib.dll are present in the game directory.

set -eu

DEST="$HOME/games/terraria"
INSTALLER="${1:-}"

if [ -z "$INSTALLER" ] || [ ! -f "$INSTALLER" ]; then
    cat << 'USAGE'
Usage: terraria.sh /path/to/terraria_installer.sh

You need the GOG Linux installer for Terraria. Download it from your GOG
library on a desktop and copy the .sh file across.
USAGE
    exit 1
fi

echo "==> Installing dependencies"
pkg install -y mono unzip
pkg install -y mesa-vulkan-icd-freedreno vulkan-loader

echo "==> Extracting the GOG installer"
mkdir -p "$DEST/game"
unzip -o "$INSTALLER" -d "$DEST/game" || true

GAMEDIR="$DEST/game/data/noarch/game"
[ -f "$GAMEDIR/Terraria.exe" ] || {
    echo "Terraria.exe not found after extracting."
    echo "The installer may be incomplete - check its size against GOG."
    exit 1
}

echo "==> Checking the extraction"
for f in FNA.dll mscorlib.dll; do
    [ -f "$GAMEDIR/$f" ] || echo "  WARNING: $f is missing - the game will not start"
done

echo "==> Writing launcher"
cat > "$DEST/run.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Terraria - native Mono, rendering through Turnip.
export DISPLAY=:0
export VK_ICD_FILENAMES=/data/data/com.termux/files/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json
export FNA3D_VSYNC=0
cd "$HOME/games/terraria/game/data/noarch/game"
exec mono Terraria.exe "$@"
EOF
chmod +x "$DEST/run.sh"

cat << 'EOF'

Terraria installed to ~/games/terraria

Start Termux:X11, then run:
  ~/games/terraria/run.sh
EOF
