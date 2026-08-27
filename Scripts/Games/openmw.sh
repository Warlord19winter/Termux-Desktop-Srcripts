#!/data/data/com.termux/files/usr/bin/bash
# OpenMW - the Morrowind engine, reimplemented
#
# Usage: openmw.sh [/path/to/Morrowind/Data Files]
#
# OpenMW replaces Morrowind's executable but still needs the original
# game's data files. Those are identical whichever installer they came
# from - GOG, Steam or a retail disc - so you can copy a Data Files
# directory across from a PC rather than installing Morrowind here.
#
# The engine itself is a prebuilt x86_64 Linux release running under box64
# with the glibc bridge, rendering through Turnip.
#
# If you have no Data Files yet, run this without an argument to install
# the engine, then add the path to openmw.cfg later.
#
# Note on VSync: OpenMW has defaulted to adaptive VSync since 0.46, which
# does not sync when the framerate falls below the refresh rate. On a
# phone it usually does. Setting non-adaptive VSync and true fullscreen in
# settings.cfg reduces tearing noticeably.

set -eu

VERSION="0.51.0"
DEST="$HOME/games/openmw"
DATAFILES="${1:-}"

echo "==> Installing dependencies"
pkg install -y glibc-runner box64-glibc curl pulseaudio
pkg install -y mesa-vulkan-icd-freedreno vulkan-loader

echo "==> Downloading OpenMW $VERSION"
mkdir -p "$DEST"
cd "$DEST"
TARBALL="openmw-${VERSION}-Linux-64Bit.tar.gz"
if [ ! -d "openmw-${VERSION}-Linux-64Bit" ]; then
    URL="https://github.com/OpenMW/openmw/releases/download/openmw-${VERSION}/$TARBALL"
    curl -fL "$URL" -o "$TARBALL" || {
        echo
        echo "Could not download OpenMW automatically."
        echo "Get the Linux 64-bit release from OpenMW's GitHub releases page"
        echo "and extract it into $DEST"
        exit 1
    }
    tar -xzf "$TARBALL"
    rm -f "$TARBALL"
fi

GAMEDIR="$DEST/openmw-${VERSION}-Linux-64Bit"
[ -f "$GAMEDIR/openmw.x86_64" ] || { echo "openmw.x86_64 not found."; exit 1; }
chmod +x "$GAMEDIR/openmw.x86_64"

if [ -n "$DATAFILES" ] && [ -d "$DATAFILES" ]; then
    echo "==> Pointing openmw.cfg at your Morrowind data"
    if ! grep -q "^data=\"$DATAFILES\"" "$GAMEDIR/openmw.cfg" 2>/dev/null; then
        printf 'data="%s"\n' "$DATAFILES" >> "$GAMEDIR/openmw.cfg"
        printf 'fallback-archive=Morrowind.bsa\n' >> "$GAMEDIR/openmw.cfg"
        for bsa in Tribunal Bloodmoon; do
            [ -f "$DATAFILES/$bsa.bsa" ] && \
                printf 'fallback-archive=%s.bsa\n' "$bsa" >> "$GAMEDIR/openmw.cfg"
        done
    fi
fi

echo "==> Writing launcher"
cat > "$DEST/run.sh" << EOF
#!/data/data/com.termux/files/usr/bin/bash
# OpenMW - x86_64 under box64, rendering through Turnip.
G="/data/data/com.termux/files/usr/glibc"
D="$GAMEDIR"

glibc-runner --shell "pulseaudio-start >/dev/null 2>&1; \\
export DISPLAY=:0; \\
export VK_ICD_FILENAMES=\$G/share/vulkan/icd.d/freedreno_icd.aarch64.json; \\
export TU_DEBUG=noconform; \\
export SDL_AUDIODRIVER=pulseaudio; \\
export PULSE_SERVER=127.0.0.1; \\
export LD_LIBRARY_PATH=./lib:\\\$LD_LIBRARY_PATH; \\
cd '\$D'; \\
box64 ./openmw.x86_64"
EOF
chmod +x "$DEST/run.sh"

if [ -z "$DATAFILES" ]; then
cat << EOF

OpenMW installed, but it has no Morrowind data yet.

Copy a "Data Files" directory from any Morrowind install onto your phone,
then add it to $GAMEDIR/openmw.cfg:

  data="/path/to/Morrowind/Data Files"
  fallback-archive=Morrowind.bsa
  fallback-archive=Tribunal.bsa
  fallback-archive=Bloodmoon.bsa

Leave out the Tribunal and Bloodmoon lines if you do not have the
expansions.
EOF
else
cat << EOF

OpenMW installed to $DEST

Start Termux:X11, then run:
  $DEST/run.sh
EOF
fi
