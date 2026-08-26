#!/data/data/com.termux/files/usr/bin/bash
# ============================================================================
#  openra-setup.sh - install and run OpenRA on Termux (aarch64)
# ============================================================================
#
#  OpenRA is an open-source rebuild of the Command & Conquer engine. It
#  covers three classic games, each a separate download:
#
#      ra    Red Alert          (default)
#      cnc   Tiberian Dawn
#      d2k   Dune 2000
#
#  ------------------------------------------------------------------------
#  WHY THIS ONE IS EASY
#  ------------------------------------------------------------------------
#  Self-contained .NET 6 (CoreCLR bundled), SDL2 + OpenGL. It runs under
#  box64 with no patches, no shims and no library substitutions - unusual
#  for this collection.
#
#  Two things it gets right that caused long debugging sessions elsewhere:
#
#    * It queries the desktop resolution at startup instead of saving one.
#      Tales of Maj'Eyal had a stale saved resolution and rendered its
#      entire UI offscreen - a pure white screen with the game running
#      fine behind it.
#
#    * CoreCLR initialises cleanly under box64. Worth recording, because
#      Stardew Valley dies at CoreCLR init with a silent exit 255 - so
#      that failure is specific to that game, not .NET in general.
#
#  ------------------------------------------------------------------------
#  STATUS ON TERMUX: UNSTABLE  (tested 2026-08, box64 0.4.5, Adreno 750)
#  ------------------------------------------------------------------------
#
#  The script installs OpenRA correctly. The GAME is the problem: under
#  box64 it is fundamentally unstable rather than broken in one fixable
#  place. It sometimes runs - Red Alert reached a playable skirmish, Dune
#  2000 played after retries - but nothing stays working.
#
#  EIGHT distinct failure modes were observed across the three mods, none
#  reproducible, all downstream of the same underlying memory corruption:
#
#     NullReferenceException in SslStream.ReceiveBlobAsync
#     AccessViolationException in Widget.DrawOuter
#     AccessViolationException in ThreadedGraphicsContext.RenderThread
#     "Stack is corrupted, aborting"
#     "Ask to run at NULL, will segfault"
#     NullReferenceException in Game.LoadShellMap
#     Managed "Stack overflow" in ProductionQueue.CancelUnbuildableItems
#     InvalidDataException: Non-power-of-two array 256x32 (world FBO)
#     ...plus bare SIGSEGV with no managed stack at all
#
#  Chasing individual signatures is whack-a-mole. Don't.
#
#  RULED OUT (all confirmed, don't repeat):
#    - BOX64_DYNAREC=0 still crashes -> NOT a code-translation bug.
#    - Conservative dynarec flags (SAFEFLAGS / BIGBLOCK / STRONGMEM /
#      CALLRET) change which signature you get, fix nothing.
#    - BOX64_EMULATED_LIBS=libssl.so.3 does nothing: box64 ships x86_64
#      OpenSSL 1.0.0 and 1.1 only. It PRINTS "will force the used of
#      emulated libs" and then uses the native wrapper anyway - always
#      check what actually loaded, not the banner.
#    - Clean settings.yaml, cleared content, plain retries.
#    - box64 exposes no thread stack-size option.
#
#  ONE REAL PARTIAL FIX (kept in the launcher):
#    Four flags disable OpenRA's startup HTTPS calls. box64's native
#    OpenSSL wrapper lacks SSL_state and ERR_put_error, so TLS throws on a
#    threadpool thread - and an unhandled exception there aborts the whole
#    process, even mid-match. Avoiding the calls removes that whole class
#    of crash. Worth knowing for ANY .NET game under box64.
#
#  If you want to play: launch repeatedly until one sticks. Red Alert has
#  the best odds. Expect it to die eventually.
#
#  ------------------------------------------------------------------------
#  ABOUT GAME ASSETS
#  ------------------------------------------------------------------------
#  OpenRA ships the engine, not the game data. On first launch it offers to
#  download the freeware assets automatically (EA released them) - that
#  works and needs no action beyond clicking through. If you own the
#  originals you can point it at those instead.
#
#  ------------------------------------------------------------------------
#  USAGE
#  ------------------------------------------------------------------------
#      bash openra-setup.sh              # Red Alert
#      bash openra-setup.sh cnc          # Tiberian Dawn
#      bash openra-setup.sh d2k          # Dune 2000
#      bash openra-setup.sh ra /path/to/OpenRA-Red-Alert-x86_64.AppImage
#
#  Prerequisites: box64 + the glibc bridge.
#      pkg install glibc-repo && pkg install glibc-runner && pkg install box64-glibc
#
# ============================================================================

set -uo pipefail

PREFIX_DIR="/data/data/com.termux/files/usr"
GLIBC_DIR="$PREFIX_DIR/glibc"
VK_ICD="$GLIBC_DIR/share/vulkan/icd.d/freedreno_icd.aarch64.json"

MOD="${1:-ra}"
LOCAL_FILE="${2:-}"

c_ok()   { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
c_info() { printf '\033[1;36m[ .. ]\033[0m %s\n' "$*"; }
c_warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
c_err()  { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; }
step()   { printf '\n\033[1;35m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
die()    { c_err "$*"; exit 1; }

# --- mod selection ---------------------------------------------------------
case "$MOD" in
    ra)  GAME_NAME="Red Alert";      APPIMAGE_NAME="OpenRA-Red-Alert-x86_64.AppImage" ;;
    cnc) GAME_NAME="Tiberian Dawn";  APPIMAGE_NAME="OpenRA-Tiberian-Dawn-x86_64.AppImage" ;;
    d2k) GAME_NAME="Dune 2000";      APPIMAGE_NAME="OpenRA-Dune-2000-x86_64.AppImage" ;;
    *)   die "Unknown mod '$MOD'. Use one of: ra (Red Alert), cnc (Tiberian Dawn), d2k (Dune 2000)" ;;
esac

GAME_DIR="$HOME/games/openra-$MOD"
DOWNLOAD_URL="${OPENRA_URL:-https://github.com/OpenRA/OpenRA/releases/latest/download/$APPIMAGE_NAME}"

printf '\n\033[1;34m========================================================\n'
printf '  OpenRA: %s\n' "$GAME_NAME"
printf '========================================================\033[0m\n'

# ============================================================================
step "1/5  Checks"
# ============================================================================

[ -d "$PREFIX_DIR" ] || die "Not Termux (no $PREFIX_DIR)"
[ "$(uname -m)" = "aarch64" ] || die "Need aarch64. Got: $(uname -m)"
[ -z "${RUNNING_IN_GLIBC_RUNNER:-}" ] || \
    die "You're inside a glibc-runner shell. Type 'exit' first."

command -v glibc-runner >/dev/null 2>&1 || die \
"glibc-runner not found.
    pkg install glibc-repo && pkg install glibc-runner"
[ -x "$GLIBC_DIR/bin/box64" ] || die \
"box64 not found at $GLIBC_DIR/bin/box64
    pkg install box64-glibc"

pkg install -y curl >/dev/null 2>&1
command -v curl >/dev/null 2>&1 || die "curl is required"

if [ -f "$VK_ICD" ]; then
    c_ok "Turnip Vulkan ICD found"
else
    c_warn "No Turnip ICD - will run without proper GPU acceleration"
fi

command -v pulseaudio >/dev/null 2>&1 || pkg install -y pulseaudio >/dev/null 2>&1
c_ok "Prerequisites OK"

mkdir -p "$GAME_DIR"

# ============================================================================
step "2/5  Getting OpenRA"
# ============================================================================

APPIMAGE="$GAME_DIR/$APPIMAGE_NAME"

if [ -n "$LOCAL_FILE" ]; then
    [ -f "$LOCAL_FILE" ] || die "File not found: $LOCAL_FILE"
    c_info "Using local file: $(basename "$LOCAL_FILE")"
    cp "$LOCAL_FILE" "$APPIMAGE" || die "Copy failed"
elif [ -s "$APPIMAGE" ]; then
    c_ok "AppImage already downloaded"
else
    c_info "Downloading $GAME_NAME..."
    if ! curl -fL --retry 3 -o "$APPIMAGE" "$DOWNLOAD_URL"; then
        c_err "Download failed."
        cat <<EOF

Grab it manually from:
    https://github.com/OpenRA/OpenRA/releases
(look for $APPIMAGE_NAME), then re-run:
    bash $0 $MOD /path/to/$APPIMAGE_NAME
EOF
        exit 1
    fi
fi

[ -s "$APPIMAGE" ] || die "AppImage is empty"
chmod +x "$APPIMAGE"
c_ok "AppImage ready ($(du -h "$APPIMAGE" | cut -f1))"

# ============================================================================
step "3/5  Extracting"
# ============================================================================
#
# AppImages normally self-mount through FUSE, which Android blocks for
# unprivileged apps. --appimage-extract unpacks to a plain directory instead.
# box64's "not compatible with statically linked binaries" warning here is
# expected: it refers to the AppImage launcher stub, not the game.

SQUASH="$GAME_DIR/squashfs-root"
OPENRA_DIR="$SQUASH/usr/lib/openra"

if [ -x "$OPENRA_DIR/OpenRA" ]; then
    c_ok "Already extracted"
else
    c_info "Extracting (the static-binary warning is expected)..."
    ( cd "$GAME_DIR" && glibc-runner "$GLIBC_DIR/bin/box64" \
        "$APPIMAGE" --appimage-extract ) >/dev/null 2>&1

    [ -d "$SQUASH" ] || die "Extraction produced no squashfs-root"

    # Layout has moved between releases - locate the binary rather than assume.
    if [ ! -f "$OPENRA_DIR/OpenRA" ]; then
        FOUND="$(find "$SQUASH" -name "OpenRA" -type f 2>/dev/null | head -1)"
        [ -n "$FOUND" ] || die "No OpenRA binary found under $SQUASH"
        OPENRA_DIR="$(dirname "$FOUND")"
    fi
    c_ok "Extracted"
fi

chmod +x "$OPENRA_DIR/OpenRA"

if file "$OPENRA_DIR/OpenRA" 2>/dev/null | grep -q "x86-64"; then
    c_ok "x86_64 binary confirmed (runs under box64)"
else
    c_warn "Unexpected binary architecture:"
    file "$OPENRA_DIR/OpenRA"
fi

# ============================================================================
step "4/5  Writing launcher"
# ============================================================================

cat > "$GAME_DIR/run.sh" <<EOF
#!$PREFIX_DIR/bin/bash
# OpenRA $GAME_NAME - x86_64 self-contained .NET 6 under box64.
#
# UNSTABLE. Launches often abort during startup ("Ask to run at NULL",
# stack corruption, assorted managed exceptions). Just run it again -
# two or three attempts is normal. When it does start, it plays properly.
#
# The four flags below disable OpenRA's startup HTTPS calls (news, version
# check, NAT discovery, telemetry). This is a REAL fix for one class of
# crash: box64's native OpenSSL wrapper does not implement SSL_state or
# ERR_put_error, so TLS throws on a threadpool thread - and an unhandled
# exception there aborts the whole process, even mid-match. Avoiding the
# calls avoids those aborts. Single-player needs no network once the
# content is downloaded; the online profile and server browser will still
# abort the game if used.
#
# The flags do NOT fix the startup abort. That is a separate, unsolved
# problem - see the header of openra-setup.sh for everything ruled out.
#
# Harmless warnings on launch:
#    libnuma        - server memory feature, unused here
#    DRI3 / libEGL  - fallback path notice
#    SSL_state      - the wrapper gap described above
#
# First run offers to download the freeware game assets. Say yes. If a
# crash interrupts that download, the content folder is left incomplete
# and every later launch fails on that instead:
#    rm -rf ~/.config/openra/Content/$MOD
#
# Start Termux:X11 before running.

glibc-runner --shell "pulseaudio-start >/dev/null 2>&1; \\
export VK_ICD_FILENAMES=$VK_ICD; \\
export TU_DEBUG=noconform; \\
export SDL_AUDIODRIVER=pulseaudio; \\
export PULSE_SERVER=127.0.0.1; \\
cd '$OPENRA_DIR'; \\
box64 ./OpenRA Game.Mod=$MOD Server.DiscoverNatDevices=false Game.FetchNews=false Game.CheckVersion=false Debug.SendSystemInformation=false"
EOF

chmod +x "$GAME_DIR/run.sh"
c_ok "Launcher: $GAME_DIR/run.sh"

# ============================================================================
step "5/5  Done"
# ============================================================================

cat <<EOF

\033[1;32m--------------------------------------------------------\033[0m
  Start Termux:X11, then:

      $GAME_DIR/run.sh

  IF IT CRASHES ON STARTUP, RUN IT AGAIN. OpenRA's threaded
  renderer races under emulation - a launch either takes or it
  aborts, and two or three attempts is normal. Once it starts,
  it plays fine.

  On first launch OpenRA offers to download the freeware
  game assets - accept, and it handles the rest.
\033[1;32m--------------------------------------------------------\033[0m

  Other games from the same engine:
      bash $0 cnc     # Tiberian Dawn
      bash $0 d2k     # Dune 2000

EOF
