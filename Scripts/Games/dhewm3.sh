#!/data/data/com.termux/files/usr/bin/bash
# dhewm3 - Doom 3
#
# Usage: dhewm3.sh /path/to/doom3
#
# A source port of Doom 3, built natively for aarch64. No box64, no glibc
# bridge, no emulation - it compiles straight against Termux's own SDL2 and
# OpenAL, and renders through Zink on Turnip.
#
# This is the only source build here that needed no patches at all. CMake
# detects the platform correctly and everything compiles as-is.
#
# YOU SUPPLY THE GAME DATA
#   dhewm3 needs the PC version of Doom 3 - the Xbox version's files are in
#   a different format and will not work. Copy your installation across from
#   a PC (Steam, GOG or disc) and point this script at the folder containing
#   base/.
#
#   The game must be patched to 1.3.1. Check that base/ has pak000.pk4
#   through pak008.pk4 - nine files. A 1.3.1 install also has game00.pk4
#   through game03.pk4 alongside them.
#
# PERFORMANCE
#   60 fps under Termux:X11 with XFCE. Frame pacing is somewhat uneven -
#   com_speeds shows the game's own work (game logic, renderer frontend and
#   backend) accounting for well under the total frame time, so the jitter
#   comes from presentation rather than from the game.
#
#   It also runs in sway, where the black rendering artifacts disappear
#   entirely - but pixman software compositing makes it much slower there.
#   Termux:X11 is the better choice unless the artifacts bother you more
#   than the speed does.

set -eu

SRC="$HOME/build/dhewm3"
DEST="$HOME/games/dhewm3"
JOBS="${JOBS:-8}"
GAMEDIR="${1:-}"

if [ -z "$GAMEDIR" ] || [ ! -d "$GAMEDIR/base" ]; then
    cat << 'USAGE'
Usage: dhewm3.sh /path/to/doom3

Point this at the folder containing base/ from a PC installation of
Doom 3. For example:

    dhewm3.sh ~/games/downloads/Doom\ 3

That folder needs base/pak000.pk4 through base/pak008.pk4.
USAGE
    exit 1
fi

echo "==> Checking the game data"
MISSING=0
for i in 0 1 2 3 4 5 6 7 8; do
    [ -f "$GAMEDIR/base/pak00$i.pk4" ] || { echo "  missing pak00$i.pk4"; MISSING=1; }
done
if [ "$MISSING" = "1" ]; then
    echo
    echo "The install looks incomplete. dhewm3 needs all nine pak files."
    exit 1
fi
if [ ! -f "$GAMEDIR/base/game00.pk4" ]; then
    echo "  note: no game00.pk4 - this may not be patched to 1.3.1"
fi

echo "==> Installing build dependencies"
pkg install -y git cmake clang sdl2 openal-soft libcurl

echo "==> Cloning dhewm3"
rm -rf "$SRC"
git clone https://github.com/dhewm/dhewm3 "$SRC"

echo "==> Configuring"
mkdir -p "$SRC/build"
cd "$SRC/build"
cmake ../neo/

echo "==> Building"
make -j"$JOBS"

echo "==> Writing launcher"
mkdir -p "$DEST"
cat > "$DEST/run.sh" << EOF
#!/data/data/com.termux/files/usr/bin/bash
# Doom 3 via dhewm3 - native aarch64, rendering through Zink on Turnip.
#
# Useful console variables (Ctrl+Alt+~ opens the console):
#   com_showFPS 1     frame rate on screen
#   com_speeds 1      per-frame timing breakdown in the terminal
#   r_mode -1         use r_customWidth / r_customHeight
#
# The expansion, Resurrection of Evil, needs: run.sh +set fs_game d3xp

export DISPLAY=\${DISPLAY:-:0}
cd "$SRC/build"
# Soft particles cause black flickering artifacts under Termux:X11 -
# they sample the depth buffer, and Zink on Turnip gets that wrong.
# Confirmed on two Adreno 750 devices. Post-processing is fine; it is
# specifically this. Pass +set r_useSoftParticles 1 to turn them back on.
exec ./dhewm3 +set fs_basepath "$GAMEDIR" +set r_useSoftParticles 0 "\$@"
EOF
chmod +x "$DEST/run.sh"

cat << EOF

Doom 3 installed.

Start Termux:X11, then run:
  ~/games/dhewm3/run.sh

For Resurrection of Evil (if you have d3xp/ in your game folder):
  ~/games/dhewm3/run.sh +set fs_game d3xp

Note the binary lives in $SRC/build - do not delete that tree.
EOF
