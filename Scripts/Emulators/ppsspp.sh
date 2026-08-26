#!/data/data/com.termux/files/usr/bin/bash
# ============================================================================
#  ppsspp-setup.sh
#  PPSSPP (PSP emulator) on Termux - built from source, native ARM64
# ============================================================================
#
#  PPSSPP isn't packaged for Termux (checked: 5025 packages, no match), so
#  this builds it from https://github.com/hrydgard/ppsspp
#
#  WHY BUILD RATHER THAN EMULATE
#  PPSSPP's JIT targets ARM64 directly and its Vulkan backend talks to Turnip
#  natively - so nothing is translated except the PSP itself. Same reasoning
#  that made DuckStation and PCSX-ReARMed work well, and that made the
#  x86_64-under-box64 emulators a dead end.
#
#  ------------------------------------------------------------------------
#  EXPECTATIONS - READ THIS
#  ------------------------------------------------------------------------
#  * This build is NOT a well-trodden path. PPSSPP officially supports Linux
#    (glibc) and Android (via the NDK). Termux is a third thing: Linux-shaped
#    but Bionic. Expect to iterate on compile errors.
#  * Disk: the repo with submodules is large, and the build tree larger.
#    Budget ~4-6GB free. Check with: df -h ~
#  * Time: this is a big C++ project. Comparable to the Prism Launcher build,
#    not the pcsx-rearmed install.
#
#  If you just want to PLAY PSP games, the official PPSSPP Android APK is
#  native ARM64, free, and will perform better because it gets real display
#  and input access instead of going through Termux:X11. Build this if you
#  want it inside the Termux desktop alongside everything else.
#
#  Usage:
#      bash ppsspp-setup.sh
#      JOBS=6 bash ppsspp-setup.sh        # more parallel jobs
#      SKIP_CLONE=1 bash ppsspp-setup.sh  # re-run build on existing checkout
#
# ============================================================================

set -uo pipefail

SRC="$HOME/build/ppsspp"
JOBS="${JOBS:-4}"
SKIP_CLONE="${SKIP_CLONE:-0}"

c_ok()   { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
c_info() { printf '\033[1;36m[ .. ]\033[0m %s\n' "$*"; }
c_warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
step()   { printf '\n\033[1;35m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
die()    { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

printf '\n\033[1;34m===============================================\n'
printf '  PPSSPP (PSP) - build from source\n'
printf '===============================================\033[0m\n'

[ -d /data/data/com.termux/files/usr ] || die "Not Termux"
[ "$(uname -m)" = "aarch64" ] || die "Need aarch64"

# ============================================================================
step "1/5  Disk space"
# ============================================================================
AVAIL=$(df -k "$HOME" | awk 'NR==2{print int($4/1024/1024)}')
echo "  ~${AVAIL}GB free"
if [ "${AVAIL:-0}" -lt 5 ]; then
    c_warn "Under 5GB free - the clone plus build tree may not fit."
    printf "  Continue anyway? [y/N] "
    read -r yn; case "$yn" in [Yy]*) ;; *) exit 1 ;; esac
else
    c_ok "enough space"
fi

# ============================================================================
step "2/5  Build dependencies"
# ============================================================================
# PPSSPP vendors most of its dependencies as submodules. These are the ones
# it wants from the system.
c_info "installing toolchain + libs..."
pkg install -y git cmake ninja clang make pkg-config \
               sdl2 zlib libzip vulkan-headers vulkan-loader-generic \
               ffmpeg libpng libsnappy >/dev/null 2>&1

for c in git cmake ninja clang; do
    command -v $c >/dev/null || die "$c missing after install"
done
c_ok "toolchain ready"

# ============================================================================
step "3/5  Source"
# ============================================================================
# --recursive is NOT optional: PPSSPP keeps ffmpeg, glslang, SPIRV-Cross and
# more as submodules. A non-recursive clone fails at configure time with
# confusing "directory not found" errors.
if [ "$SKIP_CLONE" = "1" ] && [ -d "$SRC/.git" ]; then
    c_ok "SKIP_CLONE - using existing checkout"
elif [ -d "$SRC/.git" ]; then
    c_ok "already cloned"
    c_info "updating submodules..."
    ( cd "$SRC" && git submodule update --init --recursive >/dev/null 2>&1 )
else
    mkdir -p "$HOME/build"
    c_info "cloning (large - submodules included)..."
    git clone --recursive --depth 1 https://github.com/hrydgard/ppsspp.git "$SRC" \
        || die "clone failed"
    c_ok "cloned"
fi

# ============================================================================
step "4/5  Configure + build"
# ============================================================================
#  -DUSING_QT_UI=OFF     : build the SDL frontend, not the Qt one
#  -DUSE_SYSTEM_FFMPEG=ON: use Termux's ffmpeg rather than building the
#                          bundled one, which is where Termux builds usually
#                          fall over first. If configure complains about
#                          ffmpeg versions, set this OFF and let it build its
#                          own (slower, but self-contained).
#  -DUSE_WAYLAND_WSI=OFF : we present through X11 (Termux:X11), not Wayland.
#  LTO off               : memory-hungry, and this is a phone.

cd "$SRC" || die "cannot enter $SRC"
rm -rf build

c_info "configuring..."
cmake -S . -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DUSING_QT_UI=OFF \
    -DUSE_SYSTEM_FFMPEG=ON \
    -DUSE_WAYLAND_WSI=OFF \
    -DUSE_DISCORD=OFF \
    > configure.log 2>&1

if [ $? -ne 0 ]; then
    c_warn "configure failed with system ffmpeg; retrying with the bundled one"
    cmake -S . -B build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DUSING_QT_UI=OFF \
        -DUSE_SYSTEM_FFMPEG=OFF \
        -DUSE_WAYLAND_WSI=OFF \
        -DUSE_DISCORD=OFF \
        > configure.log 2>&1 \
      || { c_warn "configure failed. Last lines:"; tail -25 configure.log; exit 1; }
fi
c_ok "configured"

c_info "building with -j$JOBS (long - go do something else)..."
if ! cmake --build build -j"$JOBS" > build.log 2>&1; then
    printf '\033[1;31m[FAIL]\033[0m build failed. Errors:\n'
    grep -E "error:|FAILED" build.log | head -20
    echo ""
    echo "  full log: $SRC/build.log"
    echo "  Common fixes:"
    echo "    * ffmpeg trouble  -> SKIP_CLONE=1, edit this script to"
    echo "                         USE_SYSTEM_FFMPEG=OFF, re-run"
    echo "    * out of memory   -> JOBS=2 bash ppsspp-setup.sh"
    exit 1
fi

BIN=$(find "$SRC/build" -maxdepth 2 -name "PPSSPPSDL" -type f | head -1)
[ -n "$BIN" ] || BIN=$(find "$SRC/build" -maxdepth 2 -name "PPSSPP*" -type f -executable | head -1)
[ -n "$BIN" ] || die "build succeeded but no PPSSPP binary found under $SRC/build"
c_ok "built: $BIN"

# ============================================================================
step "5/5  Launcher"
# ============================================================================
# PPSSPP looks for its assets/ directory relative to the binary, so the
# launcher cd's into the build directory rather than calling it by path.

mkdir -p "$HOME/games/ppsspp"
BINDIR=$(dirname "$BIN")
BINNAME=$(basename "$BIN")

cat > "$HOME/games/ppsspp/run.sh" <<RUNEOF
#!/data/data/com.termux/files/usr/bin/bash
# PPSSPP (PSP) - built from source, native ARM64. No box64, no glibc bridge.
#
# Its JIT emits ARM64 directly and the Vulkan backend talks to Turnip, so
# only the PSP itself is emulated.
#
# PPSSPP finds assets/ relative to its own binary, hence the cd below.
#
# In the app: Settings -> Graphics -> Backend = Vulkan, and raise the
# rendering resolution - an Adreno 750 has plenty of headroom for PSP.
#
# Usage:  run.sh                    -> UI
#         run.sh /path/game.iso     -> boot a game
#
# Start Termux:X11 before running.

pulseaudio-start >/dev/null 2>&1
export DISPLAY="\${DISPLAY:-:0}"
export SDL_AUDIODRIVER=pulseaudio
export PULSE_SERVER=127.0.0.1
export VK_ICD_FILENAMES=/data/data/com.termux/files/usr/glibc/share/vulkan/icd.d/freedreno_icd.aarch64.json
export TU_DEBUG=noconform

cd "$BINDIR" || exit 1
exec ./$BINNAME "\$@"
RUNEOF
chmod +x "$HOME/games/ppsspp/run.sh"
bash -n "$HOME/games/ppsspp/run.sh" || c_warn "launcher has a syntax problem"
c_ok "launcher: ~/games/ppsspp/run.sh"

printf '\n\033[1;32m-----------------------------------------------\033[0m\n'
cat <<DONE
  Start Termux:X11, then:

      ~/games/ppsspp/run.sh
      ~/games/ppsspp/run.sh /path/to/Game.iso

  In the app:
    Settings -> Graphics -> Backend: Vulkan
    Settings -> Graphics -> Rendering Resolution: 2x or higher

  No BIOS needed - PPSSPP has no firmware requirement.
DONE
printf '\033[1;32m-----------------------------------------------\033[0m\n\n'
