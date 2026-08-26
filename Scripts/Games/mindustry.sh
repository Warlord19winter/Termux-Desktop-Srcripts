#!/data/data/com.termux/files/usr/bin/bash
# ============================================================================
#  mindustry-setup.sh - install and run Mindustry on Termux (aarch64)
# ============================================================================
#
#  Self-contained. Downloads everything it needs.
#
#  ------------------------------------------------------------------------
#  WHY THIS RUNS x86_64 UNDER box64 INSTEAD OF NATIVE ARM64 JAVA
#  ------------------------------------------------------------------------
#
#  Mindustry uses Arc (its own framework), and the desktop jar bundles ARM64
#  natives for most things - libarcarm64.so, libarc-freetypearm64.so and so
#  on. So native ARM64 Java looks like it should work.
#
#  It doesn't. Arc's SDL backend native, libsdl-arcarm64.so, is not in any
#  official build. Not on GitHub, not on itch, not in the Flatpak. Running
#  on native ARM64 Java fails immediately with:
#
#      Couldn't load shared library 'libsdl-arcarm64.so'
#
#  This is long-standing and affects every ARM64 Linux user (Asahi, AUR,
#  Raspberry Pi). The x86_64 native (libsdl-arc64.so) IS shipped - so the
#  fix is to run the entire stack as x86_64 under box64, where every native
#  matches. Hence the x86_64 JRE below.
#
#  ------------------------------------------------------------------------
#  WHY -Xint (do not remove this)
#  ------------------------------------------------------------------------
#
#  Running a JVM under box64 means a JIT inside a JIT: the JVM emits x86_64
#  machine code at runtime, and box64 must then translate that freshly
#  generated code. Something in the JVM's array/buffer intrinsics gets
#  mistranslated. Every crash showed a null or corrupted buffer in a
#  file-reading path, e.g.:
#
#      NullPointerException ... at java.io.BufferedReader.readLine
#      Cannot read the array length because "<parameter1>" is null
#      IOException: Error reading region "meta"
#
#  Ruled out by testing:
#      -XX:TieredStopAtLevel=1  (C2 off)  -> still crashed
#      C1 alone                           -> crashed harder (JVM fatal error)
#      BOX64_DYNAREC_STRONGMEM=3          -> changed symptom, didn't fix
#
#  Only -Xint, which stops the JVM emitting native code at all, is stable.
#  box64 itself already hides SSE4.2 from the JVM for related reasons - it
#  auto-detects libjvm and applies its own tuning, visible at launch.
#
#  Cost: ~30s startup. In-game framerate is fine; Mindustry is 2D and the
#  heavy lifting is on the GPU.
#
#  ------------------------------------------------------------------------
#  USAGE
#  ------------------------------------------------------------------------
#      bash mindustry-setup.sh                    # download everything
#      bash mindustry-setup.sh <mindustry.zip>    # use a local itch/GOG zip
#      JIT=1 bash mindustry-setup.sh              # build launcher without
#                                                 # -Xint (expect crashes)
#
#  Prerequisites: box64 + the glibc bridge. Run 00-setup-base.sh first, or:
#      pkg install glibc-repo && pkg install glibc-runner && pkg install box64-glibc
#
# ============================================================================

set -uo pipefail

PREFIX_DIR="/data/data/com.termux/files/usr"
GLIBC_DIR="$PREFIX_DIR/glibc"
GAME_DIR="$HOME/games/mindustry"
WORK_DIR="$GAME_DIR/.setup"
VK_ICD="$GLIBC_DIR/share/vulkan/icd.d/freedreno_icd.aarch64.json"

# Official desktop jar. "latest" redirects to the current release.
MINDUSTRY_URL="${MINDUSTRY_URL:-https://github.com/Anuken/Mindustry/releases/latest/download/Mindustry.jar}"

# x86_64 JRE from Adoptium. 21 is LTS and well-established; the bundled
# Java 25 in some builds is very new and no better under emulation.
JRE_URL="${JRE_URL:-https://api.adoptium.net/v3/binary/latest/21/ga/linux/x64/jre/hotspot/normal/eclipse}"

LOCAL_ZIP="${1:-}"
JIT="${JIT:-0}"

c_ok()   { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
c_info() { printf '\033[1;36m[ .. ]\033[0m %s\n' "$*"; }
c_warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
c_err()  { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; }
step()   { printf '\n\033[1;35m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
die()    { c_err "$*"; exit 1; }

printf '\n\033[1;34m========================================================\n'
printf '  Mindustry on Termux\n'
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

pkg install -y curl unzip >/dev/null 2>&1
for c in curl unzip tar; do
    command -v "$c" >/dev/null 2>&1 || die "Missing required command: $c"
done

if [ -f "$VK_ICD" ]; then
    c_ok "Turnip Vulkan ICD found"
else
    c_warn "No Turnip ICD at $VK_ICD"
    c_warn "Game will run but without proper GPU acceleration."
fi

command -v pulseaudio >/dev/null 2>&1 || pkg install -y pulseaudio >/dev/null 2>&1
c_ok "Prerequisites OK"

mkdir -p "$GAME_DIR" "$WORK_DIR"

# ============================================================================
step "2/5  Getting Mindustry"
# ============================================================================

JAR=""
JAVA_BIN=""

if [ -n "$LOCAL_ZIP" ]; then
    # itch.io / GOG style bundle: ships desktop.jar AND its own x86_64 JRE.
    [ -f "$LOCAL_ZIP" ] || die "File not found: $LOCAL_ZIP"
    c_info "Using local bundle: $(basename "$LOCAL_ZIP")"
    unzip -q -o "$LOCAL_ZIP" -d "$GAME_DIR" || die "Extraction failed"

    JAR="$(find "$GAME_DIR" -maxdepth 3 -iname "*.jar" -size +10M 2>/dev/null | head -1)"
    JAVA_BIN="$(find "$GAME_DIR" -maxdepth 4 -type f -name java 2>/dev/null | head -1)"

    [ -n "$JAR" ] || die "No large .jar found in the bundle"
    c_ok "Jar: $(basename "$JAR")"

    if [ -n "$JAVA_BIN" ] && file "$JAVA_BIN" 2>/dev/null | grep -q "x86-64"; then
        chmod +x "$JAVA_BIN"
        c_ok "Bundled x86_64 JRE found - using it"
    else
        c_info "No usable bundled JRE - will download one"
        JAVA_BIN=""
    fi
else
    JAR="$GAME_DIR/Mindustry.jar"
    if [ -s "$JAR" ]; then
        c_ok "Mindustry.jar already present"
    else
        c_info "Downloading Mindustry..."
        if ! curl -fL --retry 3 -o "$JAR" "$MINDUSTRY_URL"; then
            c_err "Download failed."
            cat <<EOF

Get Mindustry.jar manually from:
    https://github.com/Anuken/Mindustry/releases
and place it at:
    $JAR
then re-run. Or pass an itch/GOG zip:
    bash $0 /path/to/mindustry-linux-64-bit.zip
EOF
            exit 1
        fi
        c_ok "Downloaded ($(du -h "$JAR" | cut -f1))"
    fi
fi

# Sanity: the x86_64 SDL native must be in the jar, since that is the whole
# reason this runs emulated rather than native.
if unzip -l "$JAR" 2>/dev/null | grep -q "libsdl-arc64.so"; then
    c_ok "x86_64 SDL native present in jar"
else
    c_warn "libsdl-arc64.so not found in the jar - this build may not work"
fi

# ============================================================================
step "3/5  x86_64 Java runtime"
# ============================================================================
#
# Native ARM64 Java cannot be used: the jar has no libsdl-arcarm64.so.
# The JRE must be x86_64 so it matches the SDL native.

if [ -n "$JAVA_BIN" ]; then
    c_ok "Using bundled JRE: $JAVA_BIN"
else
    JAVA_BIN="$(find "$GAME_DIR/jre-x64" -type f -name java 2>/dev/null | head -1)"
    if [ -n "$JAVA_BIN" ]; then
        c_ok "x86_64 JRE already installed"
    else
        c_info "Downloading x86_64 JRE (Temurin 21)..."
        if ! curl -fL --retry 3 -o "$WORK_DIR/jre.tar.gz" "$JRE_URL"; then
            c_err "JRE download failed."
            cat <<EOF

Get a LINUX x64 JRE manually from https://adoptium.net/
(x64 - NOT aarch64: it must match the x86_64 SDL native),
extract it to  $GAME_DIR/jre-x64/  and re-run.
EOF
            exit 1
        fi
        mkdir -p "$GAME_DIR/jre-x64"
        tar xzf "$WORK_DIR/jre.tar.gz" -C "$GAME_DIR/jre-x64" --strip-components=1 \
            || die "JRE extraction failed"
        JAVA_BIN="$(find "$GAME_DIR/jre-x64" -type f -name java 2>/dev/null | head -1)"
        [ -n "$JAVA_BIN" ] || die "No java binary in the extracted JRE"
        c_ok "JRE installed"
    fi
fi

chmod +x "$JAVA_BIN"
if file "$JAVA_BIN" 2>/dev/null | grep -q "x86-64"; then
    c_ok "Confirmed x86_64 java binary"
else
    c_err "That java binary is not x86_64:"
    file "$JAVA_BIN" >&2
    die "An ARM64 JRE cannot work - the jar has no ARM64 SDL native."
fi

# ============================================================================
step "4/5  Writing launcher"
# ============================================================================

if [ "$JIT" = "1" ]; then
    JFLAGS=""
    c_warn "JIT=1 set - building launcher WITHOUT -Xint."
    c_warn "Expect crashes with null buffers while loading assets."
else
    JFLAGS="-Xint "
fi

cat > "$GAME_DIR/run.sh" <<EOF
#!$PREFIX_DIR/bin/bash
# Mindustry launcher - x86_64 stack under box64.
#
# -Xint is load-bearing. Mindustry ships no ARM64 SDL native, so everything
# runs x86_64 under box64. That puts a JIT inside a JIT, and the JVM's
# array/buffer intrinsics get mistranslated - crashes show null buffers
# while reading files. Disabling C2, disabling C1, and raising box64's
# memory-ordering strictness all failed; only -Xint is stable.
#
# Start Termux:X11 before running.

glibc-runner --shell "pulseaudio-start >/dev/null 2>&1; \\
export VK_ICD_FILENAMES=$VK_ICD; \\
export TU_DEBUG=noconform; \\
export SDL_AUDIODRIVER=pulseaudio; \\
export PULSE_SERVER=127.0.0.1; \\
cd '$GAME_DIR'; \\
box64 '$JAVA_BIN' ${JFLAGS}-jar '$JAR'"
EOF

chmod +x "$GAME_DIR/run.sh"
c_ok "Launcher: $GAME_DIR/run.sh"

# ============================================================================
step "5/5  Done"
# ============================================================================

rm -rf "$WORK_DIR"

cat <<EOF

\033[1;32m--------------------------------------------------------\033[0m
  Start Termux:X11, then:

      $GAME_DIR/run.sh

  First load takes ~30s (interpreted JVM). Gameplay is fine.
\033[1;32m--------------------------------------------------------\033[0m

  Expected harmless messages:
    - "libjvm detected, disable Dynarec BigBlock..."  box64 auto-tuning
    - "CPUID command 24 unsupported"
    - "Failed to load base settings file"            first run only

EOF
