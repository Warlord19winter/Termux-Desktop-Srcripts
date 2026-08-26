#!/data/data/com.termux/files/usr/bin/bash
#
# ============================================================================
#  RetroArch on Termux (Android, aarch64) - automated setup
# ============================================================================
#
#  Runs the x86_64 Linux RetroArch AppImage under box64 + the Termux glibc
#  bridge, GPU-accelerated via the Turnip (Adreno) Vulkan driver.
#
#  Two non-obvious fixes are applied automatically, both discovered the hard
#  way and required for this to work at all:
#
#    1. libjack.so.0 - box64 hard-fails loading it. JACK audio is optional
#       (we use PulseAudio), so the ELF NEEDED entry is stripped outright
#       with patchelf. A stub .so does NOT work here.
#
#    2. FcLangNormalize - box64's *native* libfontconfig wrapper only
#       implements a subset of the library's functions, and this one is
#       missing. Installing a different native fontconfig does not help,
#       because the gap is in box64's own glue code. Fix: drop a real
#       x86_64 libfontconfig.so.1 next to the binary and force box64 to
#       fully emulate it via BOX64_EMULATED_LIBS.
#
#  TESTED ON: Samsung S24 Ultra (Adreno 750), Android, Termux + glibc repo.
#  Other Adreno devices should work. Mali devices will likely need a
#  different Vulkan driver than Turnip.
#
#  Usage:
#     bash setup-retroarch-termux.sh              # download RetroArch
#     bash setup-retroarch-termux.sh /path/to/RetroArch.7z   # use local file
#
# ============================================================================

set -uo pipefail

# ---------------------------------------------------------------- config ---
PREFIX_DIR="/data/data/com.termux/files/usr"
GLIBC_DIR="$PREFIX_DIR/glibc"
INSTALL_DIR="$HOME/games/retroarch"
WORK_DIR="$INSTALL_DIR/.setup"

# RetroArch stable build. If this 404s, check https://buildbot.libretro.com/
# for the current version number and override with RETROARCH_URL=... 
RETROARCH_URL="${RETROARCH_URL:-https://buildbot.libretro.com/nightly/linux/x86_64/RetroArch.7z}"

# Real x86_64 fontconfig. If this 404s (Debian rotates point releases out of
# the pool), browse https://ftp.debian.org/debian/pool/main/f/fontconfig/
# and override with FONTCONFIG_URL=...
FONTCONFIG_URL="${FONTCONFIG_URL:-https://ftp.debian.org/debian/pool/main/f/fontconfig/libfontconfig1_2.15.0-2.3_amd64.deb}"

LOCAL_ARCHIVE="${1:-}"

# ---------------------------------------------------------------- output ---
c_ok()   { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
c_info() { printf '\033[1;36m[ .. ]\033[0m %s\n' "$*"; }
c_warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
c_err()  { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; }
step()   { printf '\n\033[1;35m==>\033[0m \033[1m%s\033[0m\n' "$*"; }

die() { c_err "$*"; exit 1; }

# ============================================================================
step "1/8  Checking environment"
# ============================================================================

[ -d "$PREFIX_DIR" ] || die "This doesn't look like Termux (no $PREFIX_DIR)."

ARCH="$(uname -m)"
[ "$ARCH" = "aarch64" ] || die "Need aarch64 Android. Detected: $ARCH"
c_ok "Termux on aarch64"

if [ -n "$LOCAL_ARCHIVE" ] && [ ! -f "$LOCAL_ARCHIVE" ]; then
    die "Local archive not found: $LOCAL_ARCHIVE"
fi

# Don't run nested inside glibc-runner - it breaks the launcher later.
if [ -n "${RUNNING_IN_GLIBC_RUNNER:-}" ]; then
    die "You're inside a glibc-runner shell. Type 'exit' first, then re-run."
fi
c_ok "Not nested inside glibc-runner"

# ============================================================================
step "2/8  Installing Termux packages"
# ============================================================================

c_info "Refreshing package lists (this can take a minute)..."
pkg update -y >/dev/null 2>&1 || c_warn "pkg update had issues; continuing"

# p7zip     - unpack the RetroArch.7z
# patchelf  - strip the libjack dependency (fix #1)
# curl      - downloads
# binutils  - provides 'ar' for unpacking the Debian .deb
for p in p7zip patchelf curl binutils; do
    if pkg install -y "$p" >/dev/null 2>&1; then
        c_ok "$p"
    else
        c_warn "Could not install $p via pkg - will verify below"
    fi
done

MISSING=""
for c in 7z patchelf curl ar tar; do
    command -v "$c" >/dev/null 2>&1 || MISSING="$MISSING $c"
done
[ -z "$MISSING" ] || die "Missing required commands:$MISSING
Install them manually, then re-run this script."
c_ok "All required tools present"

# ============================================================================
step "3/8  Checking glibc bridge + box64"
# ============================================================================
#
# RetroArch here is a real x86_64 Linux binary. It needs:
#   - the Termux glibc environment (Android's Bionic libc is not compatible)
#   - box64 to translate x86_64 -> aarch64
#
# These are a substantial setup in their own right. If they're missing this
# script stops with instructions rather than guessing at package names,
# because a half-installed glibc environment is worse than none.

if ! command -v glibc-runner >/dev/null 2>&1; then
    c_err "glibc-runner not found."
    cat <<'EOF'

RetroArch's Linux build is x86_64 and needs the Termux glibc bridge.
Set it up first:

    pkg install glibc-repo
    pkg install glibc-runner

Then re-run this script. (Package names occasionally change - if those
fail, search with:  pkg search glibc )
EOF
    exit 1
fi
c_ok "glibc-runner found"

if [ ! -x "$GLIBC_DIR/bin/box64" ]; then
    c_err "box64 not found at $GLIBC_DIR/bin/box64"
    cat <<'EOF'

box64 translates x86_64 binaries to aarch64. Install the glibc build:

    pkg install box64-glibc

If that package name doesn't resolve, try:  pkg search box64
Then re-run this script.
EOF
    exit 1
fi
c_ok "box64 found"

# PulseAudio carries game audio. Android blocks /dev/snd, so ALSA won't work.
if command -v pulseaudio >/dev/null 2>&1 || command -v pulseaudio-start >/dev/null 2>&1; then
    c_ok "PulseAudio present"
else
    c_warn "PulseAudio not found - installing (needed for audio)"
    pkg install -y pulseaudio >/dev/null 2>&1 || c_warn "Install failed; RetroArch will run but stay silent"
fi

# --- GPU driver check (informational) ---------------------------------------
# The patched Turnip driver gives real GPU acceleration on Adreno. Without it
# RetroArch still runs, just slower (software/less complete GL).
VK_ICD="$GLIBC_DIR/share/vulkan/icd.d/freedreno_icd.aarch64.json"
if [ -f "$VK_ICD" ]; then
    c_ok "Turnip Vulkan ICD found"
else
    c_warn "Turnip Vulkan ICD not found at:"
    c_warn "  $VK_ICD"
    c_warn "RetroArch will still launch, but without proper GPU acceleration."
    c_warn "For Adreno GPUs, install:  pkg install mesa-vulkan-icd-freedreno-glibc"
    c_warn "(A community-patched Turnip build performs noticeably better.)"
fi

mkdir -p "$INSTALL_DIR" "$WORK_DIR" || die "Could not create $INSTALL_DIR"

# ============================================================================
step "4/8  Obtaining RetroArch"
# ============================================================================

ARCHIVE="$WORK_DIR/RetroArch.7z"

if [ -n "$LOCAL_ARCHIVE" ]; then
    c_info "Using local archive: $LOCAL_ARCHIVE"
    cp "$LOCAL_ARCHIVE" "$ARCHIVE" || die "Could not copy local archive"
elif [ -s "$ARCHIVE" ]; then
    c_ok "Archive already downloaded (delete $ARCHIVE to re-fetch)"
else
    c_info "Downloading from $RETROARCH_URL"
    if ! curl -fL --retry 3 -o "$ARCHIVE" "$RETROARCH_URL"; then
        c_err "Download failed."
        cat <<EOF

The buildbot URL may have changed. Options:

  1. Browse https://buildbot.libretro.com/ , grab the x86_64 Linux
     RetroArch.7z, then re-run:
         bash $0 /path/to/RetroArch.7z

  2. Or override the URL:
         RETROARCH_URL="<url>" bash $0
EOF
        exit 1
    fi
fi

[ -s "$ARCHIVE" ] || die "Archive is empty: $ARCHIVE"
c_ok "Archive ready ($(du -h "$ARCHIVE" | cut -f1))"

# --- pull just the AppImage out of the archive ------------------------------
# NOTE: 7z does NOT shell-expand '~' in its -o flag. Always pass an absolute
# path, or it silently creates a literal directory named '~'.
APPIMAGE_PATH="$(7z l "$ARCHIVE" 2>/dev/null | grep -oE '[^ ]+\.AppImage$' | head -1)"
[ -n "$APPIMAGE_PATH" ] || die "No .AppImage found inside the archive."
c_info "Found in archive: $APPIMAGE_PATH"

APPIMAGE="$INSTALL_DIR/$(basename "$APPIMAGE_PATH")"
if [ ! -s "$APPIMAGE" ]; then
    c_info "Extracting (large archive - please wait)..."
    7z e "$ARCHIVE" -o"$INSTALL_DIR" "$APPIMAGE_PATH" -y >/dev/null \
        || die "7z extraction failed"
fi
[ -s "$APPIMAGE" ] || die "AppImage missing after extraction: $APPIMAGE"
chmod +x "$APPIMAGE"
c_ok "AppImage extracted"

# ============================================================================
step "5/8  Unpacking the AppImage"
# ============================================================================
#
# AppImages normally self-mount via FUSE. Android blocks FUSE for unprivileged
# apps, so we use the AppImage's own --appimage-extract to unpack to a plain
# folder instead. The "not compatible with statically linked binaries" warning
# from box64 here is expected and harmless - it refers to the AppImage's tiny
# launcher stub, not RetroArch itself.

SQUASH="$INSTALL_DIR/squashfs-root"
RA_BIN="$SQUASH/usr/bin/retroarch"

if [ -x "$RA_BIN" ]; then
    c_ok "Already unpacked"
else
    c_info "Unpacking (box64 warning about static binaries is expected)..."
    ( cd "$INSTALL_DIR" && glibc-runner "$GLIBC_DIR/bin/box64" \
        "$APPIMAGE" --appimage-extract ) >/dev/null 2>&1
    [ -x "$RA_BIN" ] || die "Unpack failed - no binary at $RA_BIN"
    c_ok "Unpacked to squashfs-root/"
fi

# ============================================================================
step "6/8  Fix #1 - removing the libjack dependency"
# ============================================================================
#
# box64 fails hard on libjack.so.0 and won't load RetroArch at all. JACK is an
# optional audio backend RetroArch never uses unless explicitly selected, so
# the cleanest fix is to strip the ELF NEEDED entry entirely.

if readelf -d "$RA_BIN" 2>/dev/null | grep -q 'libjack\.so\.0'; then
    [ -f "$RA_BIN.bak" ] || cp "$RA_BIN" "$RA_BIN.bak"
    if patchelf --remove-needed libjack.so.0 "$RA_BIN"; then
        c_ok "libjack.so.0 dependency removed (backup: retroarch.bak)"
    else
        die "patchelf failed. Restore with: mv $RA_BIN.bak $RA_BIN"
    fi
else
    c_ok "libjack.so.0 already absent"
fi

# ============================================================================
step "7/8  Fix #2 - real x86_64 fontconfig"
# ============================================================================
#
# box64's native libfontconfig wrapper doesn't implement FcLangNormalize, so
# RetroArch dies at PLT resolution. No native fontconfig version fixes this -
# the gap is in box64's glue code. Solution: supply a genuine x86_64
# fontconfig and force box64 to emulate it instead of wrapping the native one.

FC_TARGET="$SQUASH/usr/lib/libfontconfig.so.1"

if [ -s "$FC_TARGET" ] && file "$FC_TARGET" 2>/dev/null | grep -q 'x86-64'; then
    c_ok "x86_64 fontconfig already in place"
else
    FC_DIR="$WORK_DIR/fontconfig-x64"
    mkdir -p "$FC_DIR"
    c_info "Downloading x86_64 fontconfig from Debian..."
    if ! curl -fL --retry 3 -o "$FC_DIR/libfontconfig.deb" "$FONTCONFIG_URL"; then
        c_err "fontconfig download failed."
        cat <<EOF

Debian rotates point releases out of the pool. Browse:
    https://ftp.debian.org/debian/pool/main/f/fontconfig/
pick the current libfontconfig1_*_amd64.deb , then re-run:
    FONTCONFIG_URL="<url>" bash $0
EOF
        exit 1
    fi

    ( cd "$FC_DIR" && ar x libfontconfig.deb && tar xf data.tar.* ) \
        || die "Could not unpack the .deb"

    FC_SRC="$(find "$FC_DIR" -name 'libfontconfig.so.1.*' -type f | head -1)"
    [ -n "$FC_SRC" ] || die "No libfontconfig.so.1.* inside the .deb"

    mkdir -p "$SQUASH/usr/lib"
    cp "$FC_SRC" "$FC_TARGET" || die "Could not install fontconfig"

    file "$FC_TARGET" | grep -q 'x86-64' \
        || die "Downloaded fontconfig is not x86_64 - wrong package?"
    c_ok "x86_64 fontconfig installed into squashfs-root/usr/lib/"
fi

# ============================================================================
step "8/8  Writing launcher"
# ============================================================================

RUN_SH="$INSTALL_DIR/run.sh"
cat > "$RUN_SH" <<EOF
#!$PREFIX_DIR/bin/bash
# RetroArch launcher - box64 + glibc bridge, GPU-accelerated via Turnip.
#
# Requires (both applied by the setup script):
#   - libjack.so.0 NEEDED entry removed via patchelf
#   - real x86_64 libfontconfig.so.1 in squashfs-root/usr/lib/, forced into
#     full emulation because box64's native wrapper lacks FcLangNormalize
#
# Start Termux:X11 before running this.

RA_DIR="$SQUASH/usr/bin"

cd "\$RA_DIR" || { echo "RetroArch not found at \$RA_DIR"; exit 1; }

glibc-runner --shell "pulseaudio-start >/dev/null 2>&1; \\
export VK_ICD_FILENAMES=$VK_ICD; \\
export TU_DEBUG=noconform; \\
export SDL_AUDIODRIVER=pulseaudio; \\
export PULSE_SERVER=127.0.0.1; \\
export BOX64_EMULATED_LIBS=libfontconfig.so.1; \\
export LD_LIBRARY_PATH=\\\$LD_LIBRARY_PATH:.; \\
cd '$SQUASH/usr/bin'; \\
box64 ./retroarch"
EOF

chmod +x "$RUN_SH"
c_ok "Launcher written: $RUN_SH"

# ============================================================================
cat <<EOF

\033[1;32m========================================================\033[0m
\033[1;32m  Setup complete\033[0m
\033[1;32m========================================================\033[0m

  Start Termux:X11, then run:

      $RUN_SH

  Expected harmless messages on launch:
    - "eglXXX not found in lib libGL.so.1"  (GLX path used instead)
    - "Cannot dlopen libgamemode.so"        (optional Feral daemon)
    - "Fontconfig error: Cannot load default config file"
                                            (bundled fonts used instead)
    - "ALSA ... /dev/snd/seq Permission denied"
                                            (MIDI hw; audio goes via Pulse)

  Cores and ROMs load through RetroArch's own UI
  (Main Menu -> Load Core -> Download a Core).

  Cleanup (frees ~200MB of installer files):
      rm -rf "$WORK_DIR"

EOF
