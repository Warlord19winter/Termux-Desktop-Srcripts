#!/data/data/com.termux/files/usr/bin/bash
# RPCS3 - PlayStation 3
#
# Built from source as a native Bionic aarch64 binary. No box64, no glibc
# bridge - RPCS3's recompilers target ARM64 directly.
#
# This is a LONG build. Budget several hours and around 8 GB of free space.
# The patch fixes six things that stop it building or running under Bionic:
#
#   * vm_native.cpp - shm_open is not usable here; use memfd_create.
#   * atomic.cpp - futex_waitv raises SIGSYS on this kernel.
#   * Thread.cpp - Bionic gives threads a 1 MB stack against glibc's 8 MB,
#     which is not enough for LLVM's recursion. Also casts pthread_t,
#     which is a pointer on glibc but an integer here.
#   * aligned_malloc.hpp - posix_memalign instead of the glibc-only paths.
#   * hidapi - Termux packages hidapi-libusb, not hidapi-hidraw.
#   * ISO.cpp - a missing include.
#
# LTO is disabled: it needs more memory than a phone has.
#
# You need PS3 firmware (PS3UPDAT.PUP) of your own, installed from RPCS3's
# own menu after this finishes.

set -eu

COMMIT="8fd2ae954d80d867fd2d58795848c77d1954574b"
SRC="$HOME/build/rpcs3"
DEST="$HOME/games/rpcs3-native"
JOBS="${JOBS:-4}"
PATCH_URL="https://raw.githubusercontent.com/Warlord19winter/Termux-Desktop-Srcripts/main/Scripts/Emulators/rpcs3-termux.patch"

echo "==> Checking free space"
df -h "$HOME" | tail -1

echo "==> Installing build dependencies"
pkg install -y git cmake ninja clang ccache pkg-config
pkg install -y qt6-qtbase qt6-qtmultimedia qt6-qtsvg
pkg install -y vulkan-loader vulkan-headers glew openal-soft
pkg install -y ffmpeg libflac libiconv hidapi libusb pulseaudio

echo "==> Cloning RPCS3 at $COMMIT"
rm -rf "$SRC"
git clone https://github.com/RPCS3/rpcs3 "$SRC"
cd "$SRC"
git checkout "$COMMIT"
git submodule update --init --recursive

echo "==> Applying the Termux patch"
mkdir -p "$HOME/.cache"
PATCH_FILE="$HOME/.cache/rpcs3-termux.patch"
curl -fL "$PATCH_URL" -o "$PATCH_FILE"
git apply "$PATCH_FILE"

echo "==> Configuring"
cmake -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DUSE_NATIVE_INSTRUCTIONS=OFF \
    -DUSE_SYSTEM_FFMPEG=ON \
    -DUSE_SYSTEM_HIDAPI=ON \
    -DUSE_SYSTEM_LIBUSB=OFF \
    -DUSE_LTO=OFF \
    -DUSE_AAUDIO=OFF \
    -DCMAKE_C_COMPILER_LAUNCHER=ccache \
    -DCMAKE_CXX_COMPILER_LAUNCHER=ccache

echo "==> Building (this takes hours)"
cmake --build build -j"$JOBS"

echo "==> Installing to $DEST"
mkdir -p "$DEST" "$HOME/games/roms/ps3"
cp build/bin/rpcs3 "$DEST/"
[ -d build/bin/Icons ] && cp -r build/bin/Icons "$DEST/" || true
[ -d build/bin/GuiConfigs ] && cp -r build/bin/GuiConfigs "$DEST/" || true
[ -d build/bin/git ] && cp -r build/bin/git "$DEST/" || true
strip "$DEST/rpcs3" || true

echo "==> Writing launcher"
cat > "$DEST/run.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# RPCS3 (PS3) - native aarch64.
# Turnip has no vendor workarounds in RPCS3, so expect graphical glitches.
# Logs go to ~/.cache/rpcs3/RPCS3.log (note .cache, not .config).
cd "$(dirname "$0")"
export DISPLAY=:0
exec ./rpcs3 "$@"
EOF
chmod +x "$DEST/run.sh"

cat << 'EOF'

RPCS3 installed to ~/games/rpcs3-native

You need PS3 firmware of your own (PS3UPDAT.PUP). Install it from
File > Install Firmware inside RPCS3.

Games go in ~/games/roms/ps3/

Start with:  ~/games/rpcs3-native/run.sh

The build tree in ~/build/rpcs3 is large but worth keeping if you plan
to rebuild - ccache makes a second build much faster.
EOF
