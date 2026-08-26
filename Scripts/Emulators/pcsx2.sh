#!/data/data/com.termux/files/usr/bin/bash
# PCSX2 - PlayStation 2
#
# There is no aarch64 build of PCSX2: its recompilers are hand-written x86
# assembly, which is why AetherSX2 exists as a separate project rather than
# a port. So this runs the x86_64 Linux AppImage under box64 - a JIT inside
# a JIT. It works, but do not expect full speed.
#
# Two settings are REQUIRED and the launcher enforces them on every start:
#
#   EnableFastmem = false
#     PCSX2 reserves a very large contiguous region for the PS2 memory map
#     and catches segfaults to page it in. Android gives processes a 39-bit
#     address space, which cannot hold that reservation alongside box64's
#     own, so the fault handler crashes at a fixed address every time.
#
#   WaitLoop = false
#     EE spin-loop detection depends on accurate timing, and Turnip's
#     vkGetCalibratedTimestampsEXT returns VK_ERROR_OUT_OF_HOST_MEMORY.
#     With WaitLoop on, games hang after the PS2 boot animation.
#
# Do NOT enable MTVU (vuThread) - the extra VU thread deadlocks on exit.
# EE cycle rate/skip hacks also cause hangs; leave them at 0.
#
# ISOs must live in Termux's own storage. On /storage (Android scoped
# storage) PCSX2 cannot stat files and reports "Failed to determine file
# size" for every game.

set -eu

VERSION="v2.6.3"
FILE="pcsx2-${VERSION}-linux-appimage-x64-Qt.AppImage"
URL="https://github.com/PCSX2/pcsx2/releases/download/${VERSION}/${FILE}"
DEST="$HOME/games/pcsx2"
WORK="$HOME/.cache/pcsx2-install"

echo "==> Installing dependencies"
pkg install -y squashfs-tools-ng glibc-runner box64-glibc pulseaudio

echo "==> Downloading PCSX2 $VERSION"
mkdir -p "$WORK" && cd "$WORK"
[ -f pcsx2.AppImage ] || curl -fL "$URL" -o pcsx2.AppImage

echo "==> Extracting squashfs payload"
# The AppImage runtime contains the string "hsqs" in its own error
# messages, so take the LAST match rather than the first.
OFFSET=$(grep -abo "hsqs" pcsx2.AppImage | tail -1 | cut -d: -f1)
[ -n "$OFFSET" ] || { echo "No squashfs payload found"; exit 1; }
dd if=pcsx2.AppImage of=pcsx2.squashfs bs=4096 skip="$OFFSET" iflag=skip_bytes
sqfs2tar pcsx2.squashfs > pcsx2.tar
rm -rf root && mkdir root && tar -xf pcsx2.tar -C root

echo "==> Installing to $DEST"
mkdir -p "$DEST" "$HOME/games/roms/ps2"
cp -r root/usr/* "$DEST"/

echo "==> Writing launcher"
cat > "$DEST/run.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# PCSX2 (PS2) - x86_64 AppImage under box64.
#
# Keep ISOs in Termux storage, not /storage - PCSX2 cannot stat files on
# Android scoped storage.

DIR="$(cd "$(dirname "$0")" && pwd)"
INI="$HOME/.config/PCSX2/inis/PCSX2.ini"

# PCSX2 rewrites its config on exit, so re-apply the two required
# settings each time rather than trusting them to stick.
if [ -f "$INI" ]; then
    sed -i 's/^EnableFastmem = true/EnableFastmem = false/' "$INI"
    sed -i 's/^WaitLoop = true/WaitLoop = false/' "$INI"
fi

# The xcb family and the crypto stack must all be emulated together.
# Mixing box64's native wrappers with the AppImage's own copies leaves
# unresolved symbols (xcb_render_*, nettle_sha3_256_shake) and crashes.
EMU=libxcb-render.so.0:libxcb-render-util.so.0:libxcb-util.so.1
EMU=$EMU:libxcb-cursor.so.0:libxcb-icccm.so.4:libxcb-image.so.0
EMU=$EMU:libxcb-keysyms.so.1:libxcb-shm.so.0:libxcb-glx.so.0
EMU=$EMU:libxcb-randr.so.0:libxcb-shape.so.0:libxcb-sync.so.1
EMU=$EMU:libxcb-xfixes.so.0:libxcb-xkb.so.1
EMU=$EMU:libnettle.so.8:libgnutls.so.30:libgmp.so.10

glibc-runner --shell "export LD_LIBRARY_PATH=$DIR/lib; export DISPLAY=:0; export QT_QPA_PLATFORM=xcb; export DBUS_SESSION_BUS_ADDRESS=disabled:; export BOX64_EMULATED_LIBS=$EMU; cd '$DIR/bin'; box64 ./pcsx2-qt $*"
EOF
chmod +x "$DEST/run.sh"

echo "==> Cleaning up"
cd "$HOME" && rm -rf "$WORK"

cat << 'EOF'

PCSX2 installed to ~/games/pcsx2

Copy your ISOs into ~/games/roms/ps2/ - they will not work from
/storage/... because PCSX2 cannot read file sizes there.

You also need a PS2 BIOS image of your own.

Start with:  ~/games/pcsx2/run.sh

Expect it to be slow. Fastmem is off by necessity, and this is an
x86_64 emulator running under box64.
EOF
