#!/data/data/com.termux/files/usr/bin/bash
# Vintage Story
#
# Usage: vintagestory.sh /path/to/vs_archive.tar.gz
#
# Vintage Story ships as .NET assemblies, so Termux's own dotnet runtime
# executes them directly - no box64 and no glibc bridge. Rendering goes
# through Zink on Turnip.
#
# Known trade-off: intermittent black-line flicker on this driver stack.
# It is a rendering artifact rather than a crash, and worth the speed.
#
# You supply the archive yourself. Vintage Story is sold on
# vintagestory.at; download the Linux tar.gz from your account page.

set -eu

DEST="$HOME/games/vintagestory"
ARCHIVE="${1:-}"

if [ -z "$ARCHIVE" ] || [ ! -f "$ARCHIVE" ]; then
    cat << 'USAGE'
Usage: vintagestory.sh /path/to/vs_archive.tar.gz

Download the Linux archive from your account at vintagestory.at and copy
it across to your phone.
USAGE
    exit 1
fi

echo "==> Installing the .NET runtime"
pkg install -y dotnet-runtime-10.0
pkg install -y mesa-vulkan-icd-freedreno vulkan-loader mesa

echo "==> Extracting"
mkdir -p "$DEST/extracted"
tar -xzf "$ARCHIVE" -C "$DEST/extracted"

DLL=$(find "$DEST/extracted" -name "Vintagestory.dll" | head -1)
[ -n "$DLL" ] || { echo "Vintagestory.dll not found in the archive."; exit 1; }
GAMEDIR=$(dirname "$DLL")

echo "==> Writing launcher"
cat > "$DEST/run.sh" << EOF
#!/data/data/com.termux/files/usr/bin/bash
# Vintage Story - .NET assemblies on Termux's own dotnet runtime.
# Expect occasional black-line flicker; it is a Zink/Turnip artifact.
export DISPLAY=:0
export VK_ICD_FILENAMES=$PREFIX/share/vulkan/icd.d/freedreno_icd.aarch64.json
exec dotnet "$DLL" "\$@"
EOF
chmod +x "$DEST/run.sh"

cat << 'EOF'

Vintage Story installed to ~/games/vintagestory

Start Termux:X11, then run:
  ~/games/vintagestory/run.sh

You will need to sign in with your Vintage Story account on first launch.
EOF
