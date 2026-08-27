#!/data/data/com.termux/files/usr/bin/bash
# Vita3K - PlayStation Vita
#
# ---------------------------------------------------------------------------
# READ THIS FIRST
# ---------------------------------------------------------------------------
# This is the least reliable script here. It builds Vita3K from source with
# edits across five separate git repositories, and the build takes hours
# before it will tell you whether it worked. Expect to debug it.
#
# The prebuilt Linux aarch64 release does not run on Termux at all: SDL
# fails at startup because udev_monitor_new_from_netlink() returns NULL -
# Android blocks the netlink socket. No SDL hint bypasses it, because SDL
# sets the monitor up before any hint is read. Building with
# -DSDL_LIBUDEV=OFF is the only fix, hence all of this.
#
# The main trap: Termux's clang always defines __ANDROID__, so every
# Android code path activates even when building for Linux. SDL's own
# public header then undefines SDL_PLATFORM_LINUX, so the CMake config and
# the headers disagree about what platform this is. -U__ANDROID__ plus a
# patch to that header is what makes the tree agree.
#
# You need PS Vita firmware (PSP2UPDAT.PUP) of your own. Commercial games
# work; homebrew ports generally do not, because they call kubridge-style
# functions Vita3K has never implemented - those crash with 0xDEADBEEF
# stub writes, on desktop Vita3K too.
# ---------------------------------------------------------------------------

set -eu

COMMIT="496939b602703951277263c7b3e60a9ae36879c1"
SRC="$HOME/build/vita3k"
DEST="$HOME/games/vita3k"
JOBS="${JOBS:-4}"
PATCH_URL="https://raw.githubusercontent.com/Warlord19winter/Termux-Desktop-Srcripts/main/Scripts/Emulators/vita3k-termux.patch"

echo "==> Checking free space (need ~4 GB)"
df -h "$HOME" | tail -1

echo "==> Installing build dependencies"
pkg install -y git cmake ninja clang ccache pkg-config
pkg install -y qt6-qtbase qt6-qtsvg qt6-qtmultimedia
pkg install -y vulkan-loader vulkan-headers
pkg install -y ffmpeg openal-soft libzip boost boost-static
pkg install -y libandroid-shmem sdl2 sdl-gfx pulseaudio

echo "==> Cloning Vita3K with submodules"
rm -rf "$SRC"
git clone https://github.com/Vita3K/Vita3K "$SRC"
cd "$SRC"
git checkout "$COMMIT"
git submodule update --init --recursive

echo "==> Applying the main patch"
mkdir -p "$HOME/.cache"
PATCH_FILE="$HOME/.cache/vita3k-termux.patch"
curl -fL "$PATCH_URL" -o "$PATCH_FILE"
git apply "$PATCH_FILE"

echo "==> Patching SDL's platform detection"
python3 - <<'PYEOF'
p = 'external/sdl/include/SDL3/SDL_platform_defines.h'
s = open(p).read()
old = '#if defined(ANDROID) || defined(__ANDROID__)'
new = '#if 0 /* Termux: building for Linux, not the Android APK backend */'
assert s.count(old) == 1, 'SDL platform guard'
open(p, 'w').write(s.replace(old, new, 1))
print('  SDL platform guard disabled')
PYEOF

echo "==> Patching nativefiledialog for Bionic getrandom"
python3 - <<'PYEOF'
p = 'external/nativefiledialog-extended/src/nfd_portal.cpp'
s = open(p).read()
old = '#include <dbus/dbus.h>'
new = '''#include <dbus/dbus.h>
#if 1 /* Bionic: getrandom wrapper is gated on API level */
#include <sys/syscall.h>
#include <unistd.h>
static ssize_t getrandom(void* buf, size_t len, unsigned int flags) {
    return syscall(SYS_getrandom, buf, len, flags);
}
#endif'''
assert s.count(old) == 1, 'nfd dbus include'
open(p, 'w').write(s.replace(old, new, 1))
print('  getrandom shim added')
PYEOF

echo "==> Patching VMA for posix_memalign"
python3 - <<'PYEOF'
p = 'external/VulkanMemoryAllocator-Hpp/VulkanMemoryAllocator/include/vk_mem_alloc.h'
s = open(p).read()
old = '''#elif __cplusplus >= 201703L || _MSVC_LANG >= 201703L // C++17
static void* vma_aligned_alloc(size_t alignment, size_t size)
{
    return aligned_alloc(alignment, size);
}'''
new = '''#elif __cplusplus >= 201703L || _MSVC_LANG >= 201703L // C++17
static void* vma_aligned_alloc(size_t alignment, size_t size)
{
    void *pointer;
    if(posix_memalign(&pointer, alignment, size) == 0)
        return pointer;
    return VMA_NULL;
}'''
assert s.count(old) == 1, 'VMA aligned_alloc'
open(p, 'w').write(s.replace(old, new, 1))
print('  aligned_alloc replaced with posix_memalign')
PYEOF

echo "==> Replacing the FFmpeg CMakeLists"
cat > external/ffmpeg/CMakeLists.txt << 'FFEOF'
# Termux: link the system FFmpeg instead of Vita3K's prebuilt glibc binaries,
# which reference glibc-only symbols Bionic does not provide. The bundled
# headers are kept, since Vita3K uses internal APIs not shipped by distros.
if (NOT DEFINED FFMPEG_CORE_NAME)
	set(FFMPEG_CORE_NAME ffmpeg)
endif()
add_library(${FFMPEG_CORE_NAME} INTERFACE)
target_include_directories(${FFMPEG_CORE_NAME} INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include")
find_package(PkgConfig REQUIRED)
pkg_check_modules(SYSFFMPEG REQUIRED IMPORTED_TARGET
	libavformat libavcodec libswscale libavutil libavfilter libswresample)
target_link_libraries(${FFMPEG_CORE_NAME} INTERFACE PkgConfig::SYSFFMPEG)
FFEOF

echo "==> Configuring"
cmake -B build -G Ninja \
    -DCMAKE_SYSTEM_NAME=Linux \
    -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
    -DCMAKE_BUILD_TYPE=Release \
    -DSDL_LIBUDEV=OFF \
    -DSDL_KMSDRM=OFF \
    -DUSE_AAUDIO=OFF \
    -DUSE_OPENSL=OFF \
    -DCMAKE_CXX_FLAGS="-U__ANDROID__" \
    -DCMAKE_C_FLAGS="-U__ANDROID__" \
    -DCMAKE_EXE_LINKER_FLAGS="-landroid-shmem" \
    -DCMAKE_C_COMPILER_LAUNCHER=ccache \
    -DCMAKE_CXX_COMPILER_LAUNCHER=ccache

echo "==> Building (this takes hours)"
cmake --build build -j"$JOBS"

echo "==> Installing to $DEST"
mkdir -p "$DEST"
cp -r build/bin/* "$DEST"/

echo "==> Writing launcher"
cat > "$DEST/run.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Vita3K (PS Vita) - native aarch64, built from source.
# Install firmware from the File menu on first run.
# Homebrew ports needing kubridge will not run - that is upstream, not Termux.
cd "$(dirname "$0")"
export DISPLAY=:0
exec ./Vita3K "$@"
EOF
chmod +x "$DEST/run.sh"

cat << 'EOF'

Vita3K installed to ~/games/vita3k

First run:
  1. Start Termux:X11
  2. ~/games/vita3k/run.sh
  3. File > Install Firmware, and point it at a PSP2UPDAT.PUP of your own
  4. File > Install .vpk or .pkg for games

Files live in ~/.local/share/Vita3K/Vita3K/
Logs are in ~/.cache/Vita3K/
EOF
