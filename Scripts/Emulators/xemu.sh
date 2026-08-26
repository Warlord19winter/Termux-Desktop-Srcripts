#!/data/data/com.termux/files/usr/bin/bash
# xemu - Original Xbox emulator
#
# The aarch64 AppImage is native ARM64 but glibc-linked, so it needs
# glibc-runner rather than box64. libusb is the one library the AppImage
# does not bundle, and Termux has no glibc build of it, so we take it
# from Debian.
#
# You must supply your own BIOS, MCPX boot ROM and hard disk image.

set -eu

VERSION="0.8.136"
URL="https://github.com/xemu-project/xemu/releases/download/v${VERSION}/xemu-${VERSION}-aarch64.AppImage"
DEST="$HOME/games/xemu"
WORK="$HOME/.cache/xemu-install"

echo "==> Installing dependencies"
pkg install -y squashfs-tools-ng patchelf glibc-runner pulseaudio

echo "==> Downloading xemu $VERSION"
mkdir -p "$WORK" && cd "$WORK"
[ -f xemu.AppImage ] || curl -fL "$URL" -o xemu.AppImage

echo "==> Extracting squashfs payload"
OFFSET=$(grep -abo "hsqs" xemu.AppImage | head -1 | cut -d: -f1)
[ -n "$OFFSET" ] || { echo "No squashfs payload found"; exit 1; }
dd if=xemu.AppImage of=xemu.squashfs bs=4096 skip="$OFFSET" iflag=skip_bytes
sqfs2tar xemu.squashfs > xemu.tar
rm -rf root && mkdir root && tar -xf xemu.tar -C root

echo "==> Installing to $DEST"
mkdir -p "$DEST"
cp -r root/usr/* "$DEST"/
patchelf --set-interpreter "$PREFIX/glibc/lib/ld-linux-aarch64.so.1" "$DEST/bin/xemu"

echo "==> Fetching libusb from Debian"
DEB="libusb-1.0-0_1.0.26-1_arm64.deb"
curl -fL "http://ftp.debian.org/debian/pool/main/libu/libusb-1.0/$DEB" -o "$DEB"
ar x "$DEB" && tar -xf data.tar.xz
cp usr/lib/aarch64-linux-gnu/libusb-1.0.so.0.3.0 "$DEST/lib/libusb-1.0.so.0"

echo "==> Writing launcher"
cat > "$DEST/run.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# xemu (Original Xbox). Set BIOS/MCPX/HDD paths in
# ~/.local/share/xemu/xemu/xemu.toml before first use.
# Load a disc with: run.sh -dvd_path /path/to/game.iso
# Avoid spaces in that path - grun goes through a shell.

cd "$(dirname "$0")/bin"
export LD_LIBRARY_PATH="$HOME/games/xemu/lib"
export DISPLAY=:0

pulseaudio --check 2>/dev/null || pulseaudio --start --exit-idle-time=-1

for d in "$PREFIX"/tmp/pulse-*/; do
    if [ -S "$d/native" ] && [ -f "$d/pid" ]; then
        export SDL_AUDIODRIVER=pulseaudio
        export PULSE_SERVER="unix:${d}native"
        break
    fi
done

exec grun ./xemu "$@"
EOF
chmod +x "$DEST/run.sh"

echo "==> Cleaning up"
cd "$HOME" && rm -rf "$WORK"

cat << 'EOF'

xemu installed to ~/games/xemu

Before it will boot you need three files of your own:
  - MCPX boot ROM (mcpx_1.0.bin)
  - Xbox BIOS image
  - Xbox hard disk image (xbox_hdd.qcow2)

Set their paths in ~/.local/share/xemu/xemu/xemu.toml under [sys.files]
as bootrom_path, flashrom_path and hdd_path.

Run with:  ~/games/xemu/run.sh
EOF
