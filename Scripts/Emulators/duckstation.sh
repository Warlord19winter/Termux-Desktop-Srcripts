#!/data/data/com.termux/files/usr/bin/bash
# DuckStation - PlayStation 1
#
# The arm64 AppImage is native ARM64: DuckStation's MIPS recompiler emits
# AArch64 directly and it renders through Vulkan straight to Turnip, so
# nothing is translated except the PS1 itself. It is glibc-linked though,
# so it runs under the glibc bridge rather than box64.
#
# Four fixes are applied here, all found the hard way:
#
#   1. libsm-glibc and libice-glibc. Qt's xcb plugin needs libSM.so.6 and
#      libICE.so.6, which the AppImage does not bundle. Without them Qt
#      claims "xcb-cursor0 is needed", which is a red herring - the real
#      failure is the plugin's own missing dependencies.
#
#   2. patchelf on the interpreter. The binary wants
#      /lib/ld-linux-aarch64.so.1, which does not exist here. Invoking the
#      loader by hand instead makes DuckStation resolve its own path wrongly
#      ("Resources directory does not exist"), because it finds its
#      resources relative to the executable.
#
#   3. A libshaderc symlink next to the binary. DuckStation dlopens shaderc
#      from its executable's directory, but the AppImage ships it in
#      usr/lib. Without the link, ImGui shader compilation fails and Vulkan
#      falls back to "None".
#
#   4. $PREFIX/glibc/lib goes on LD_LIBRARY_PATH *after* the AppImage's own
#      lib directory, never before. libc.so there is a linker script rather
#      than an ELF, and a loader that reaches it first chokes
#      ("bad ELF magic: 2f2a2047", which is the text "/* G"). Appended, it
#      is only consulted for libraries the AppImage does not bundle - which
#      on a clean install is several of them.
#
# You need a real PS1 BIOS image - there is no HLE fallback.

set -eu

URL="https://github.com/stenzek/duckstation/releases/download/latest/DuckStation-arm64.AppImage"
DEST="$HOME/games/duckstation"

echo "==> Installing dependencies"
pkg install -y squashfs-tools-ng patchelf glibc-runner pulseaudio
pkg install -y libsm-glibc libice-glibc
# Qt needs these too. On a machine where other things have already been
# installed they are usually present; on a clean one they are not, and
# DuckStation fails with a chain of "cannot open shared object file".
pkg install -y fontconfig-glibc harfbuzz-glibc freetype-glibc libpng-glibc
pkg install -y libxi-glibc libxkbcommon-glibc libxcb-glibc libx11-glibc
pkg install -y libxext-glibc libxrender-glibc libglvnd-glibc mesa-glibc
pkg install -y libicu-glibc openssl-glibc zlib-glibc

echo "==> Downloading DuckStation"
mkdir -p "$DEST" && cd "$DEST"
curl -fL "$URL" -o DuckStation-arm64.AppImage

echo "==> Extracting squashfs payload"
OFFSET=$(grep -abo "hsqs" DuckStation-arm64.AppImage | head -1 | cut -d: -f1)
[ -n "$OFFSET" ] || { echo "No squashfs payload found"; exit 1; }
dd if=DuckStation-arm64.AppImage of=ds.squashfs bs=4096 skip="$OFFSET" iflag=skip_bytes
sqfs2tar ds.squashfs > ds.tar
rm -rf squashfs-root && mkdir squashfs-root && tar -xf ds.tar -C squashfs-root
rm -f ds.squashfs ds.tar

echo "==> Patching the interpreter"
patchelf --set-interpreter "$PREFIX/glibc/lib/ld-linux-aarch64.so.1" \
    "$DEST/squashfs-root/usr/bin/duckstation-qt"

echo "==> Linking libshaderc next to the binary"
ln -sf ../lib/libshaderc_shared.so "$DEST/squashfs-root/usr/bin/libshaderc_shared.so"

echo "==> Writing launcher"
mkdir -p "$HOME/games/roms/ps1"
cat > "$DEST/run.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# DuckStation (PS1) - native ARM64 under the glibc bridge.
#
# Harmless: SDL joystick/gamepad/haptic init fails - there is no gamepad
# subsystem under Termux. Keyboard input works.
#
# Start Termux:X11 before running.

D="$HOME/games/duckstation/squashfs-root"
G="/data/data/com.termux/files/usr/glibc"

glibc-runner --shell "pulseaudio-start >/dev/null 2>&1; \
export DISPLAY=:0; \
export VK_ICD_FILENAMES=$G/share/vulkan/icd.d/freedreno_icd.aarch64.json; \
export TU_DEBUG=noconform; \
export SDL_AUDIODRIVER=pulseaudio; \
export PULSE_SERVER=127.0.0.1; \
export PULSE_LATENCY_MSEC=80; \
export LD_LIBRARY_PATH=$D/usr/lib:$G/lib; \
export QT_QPA_PLATFORM=xcb; \
export QT_QPA_PLATFORM_PLUGIN_PATH=$D/usr/lib/plugins/platforms; \
export QT_PLUGIN_PATH=$D/usr/lib/plugins; \
export FONTCONFIG_PATH=$G/etc/fonts; \
cd '$D/usr/bin'; \
./duckstation-qt \"\$@\""
EOF
chmod +x "$DEST/run.sh"

cat << 'EOF'

DuckStation installed to ~/games/duckstation

You need a PS1 BIOS image of your own - there is no HLE fallback.
Add it through Settings > BIOS on first run.

Put games in ~/games/roms/ps1/ and start with:
  ~/games/duckstation/run.sh
EOF
