#!/data/data/com.termux/files/usr/bin/bash
# O2EM2 - Magnavox Odyssey 2 / Philips Videopac
#
# Built from source. The original O2EM needs Allegro 4, which is not
# packaged for Termux and would be its own project to build; montjoie's
# fork adds an SDL backend, so we use that with --with-game-api=sdl.
#
# Three things needed fixing to build under Bionic:
#
#   * usleep needs <unistd.h> included explicitly. Older compilers let the
#     implicit declaration through; modern clang does not.
#
#   * -fcommon. The headers declare variables without extern, so every
#     object file gets its own copy. GCC used to merge these; current
#     compilers reject them as duplicate symbols at link time.
#
#   * CFLAGS must be added to, not replaced. Overriding CFLAGS wholesale
#     drops -D__O2EM_SDL__ and the build falls back to Allegro.
#
# You need an Odyssey 2 BIOS image (o2rom.bin, 1024 bytes) of your own.

set -eu

SRC="$HOME/build/o2em2"
DEST="$HOME/games/o2em"

echo "==> Installing build dependencies"
pkg install -y git clang make sdl sdl-image
pkg install -y tur-repo
pkg install -y sdl-gfx

echo "==> Cloning montjoie/o2em2"
rm -rf "$SRC"
git clone https://github.com/montjoie/o2em2 "$SRC"
cd "$SRC"

echo "==> Patching vmachine.c for the missing unistd.h"
python3 - <<'PYEOF'
p = 'vmachine.c'
s = open(p).read()
old = '#include "audio.h"'
new = '#include <unistd.h>  /* usleep */\n#include "audio.h"'
if '<unistd.h>' not in s:
    assert s.count(old) == 1
    open(p, 'w').write(s.replace(old, new, 1))
PYEOF

echo "==> Configuring with the SDL backend"
./configure --with-game-api=sdl

echo "==> Building"
CF="-g -O2 -pipe -Wall -fwrapv -fcommon"
CF="$CF -I$PREFIX/include/SDL -D_GNU_SOURCE=1 -D_REENTRANT -D__O2EM_SDL__"
make CFLAGS="$CF"

echo "==> Installing to $DEST"
mkdir -p "$DEST/bios" "$DEST/roms"
cp o2em2 "$DEST/"

echo "==> Writing launcher"
cat > "$DEST/run.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# O2EM2 (Magnavox Odyssey 2 / Videopac).
#
# Needs bios/o2rom.bin. ROMs go in roms/ and are passed by filename only,
# not by full path.
#
# Controls: WASD + Space is joystick 1, arrows + right shift is joystick 2,
# ESC quits. The "appuie sur" lines are the author's French debug output
# for keypresses - harmless.

cd "$(dirname "$0")"
export DISPLAY=:0
exec ./o2em2 "$@"
EOF
chmod +x "$DEST/run.sh"

cat << 'EOF'

O2EM2 installed to ~/games/o2em

You need a BIOS image of your own: put o2rom.bin (1024 bytes) in
  ~/games/o2em/bios/

Put ROMs in ~/games/o2em/roms/ and run them by filename:
  ~/games/o2em/run.sh "Frogger (Brazil).bin"

Other BIOS images it will look for, if you have them: c52.bin (French
Videopac), jopac.bin, g7400.bin (Videopac+).
EOF
