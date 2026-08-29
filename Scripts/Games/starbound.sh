#!/data/data/com.termux/files/usr/bin/bash
# Starbound (GOG Linux build)
#
# Usage: starbound.sh /path/to/starbound_installer.sh
#
# Starbound is x86_64, so it runs under box64 with the glibc bridge.
#
# TWO THINGS MAKE THIS MORE INVOLVED THAN IT LOOKS
#
# 1. The /tmp problem. Starbound writes temp files to /tmp, which Android
#    does not allow. A small LD_PRELOAD shim intercepts mkstemp, unlink and
#    remove, and rewrites any /tmp path to a writable directory. It is
#    compiled here for x86_64, because box64 loads it into the emulated
#    process rather than the host one. The shim deliberately avoids libc
#    headers - it declares the few functions it needs itself - so it builds
#    with Termux's clang without an x86_64 sysroot.
#
# 2. Missing libraries. Starbound links against SDL2, and Termux has no
#    glibc build of it. Neither libsamplerate, libdecor nor ICU 76 (which
#    that SDL2 wants specifically) are packaged either. All four come from
#    Debian's arm64 archive here.
#
#    This is easy to miss: on a machine where other things have already
#    been installed, some of these are present as side effects and the game
#    starts anyway. On a clean install it fails with a chain of "cannot
#    open shared object file" errors, one library at a time.

set -eu

DEST="$HOME/games/starbound"
WORK="$HOME/.cache/starbound-deps"
INSTALLER="${1:-}"
DEB="http://ftp.debian.org/debian/pool/main"

if [ -z "$INSTALLER" ] || [ ! -f "$INSTALLER" ]; then
    cat << 'USAGE'
Usage: starbound.sh /path/to/starbound_installer.sh

You need the GOG Linux installer for Starbound. Download it from your GOG
library on a desktop and copy the .sh file across.
USAGE
    exit 1
fi

echo "==> Installing packaged dependencies"
pkg install -y glibc-runner box64-glibc unzip clang curl binutils pulseaudio
pkg install -y mesa-glibc mesa-vulkan-icd-freedreno-glibc vulkan-icd-loader-glibc
pkg install -y glu-glibc alsa-lib-glibc libpulse-glibc
pkg install -y libx11-glibc libxext-glibc libxcursor-glibc libxi-glibc
pkg install -y libxfixes-glibc libxrandr-glibc libxss-glibc
pkg install -y libdrm-glibc libwayland-glibc libxkbcommon-glibc

echo "==> Fetching the libraries Termux does not package"
# SDL2, libsamplerate, libdecor and ICU 76 all come from Debian arm64.
# The ICU version matters: this SDL2 links against 76 specifically, and
# Termux packages 78, which will not satisfy it.
mkdir -p "$WORK" && cd "$WORK"

fetch_deb() {
    local url="$1" name="${1##*/}"
    echo "  $name"
    [ -f "$name" ] || curl -fL "$url" -o "$name"
    ar x "$name"
    tar -xf data.tar.* 2>/dev/null || tar -xf data.tar.zst
    rm -f control.tar.* data.tar.* debian-binary
}

fetch_deb "$DEB/libs/libsdl2/libsdl2-2.0-0_2.32.4+dfsg-1_arm64.deb"
fetch_deb "$DEB/libs/libsamplerate/libsamplerate0_0.2.2-3_arm64.deb"
fetch_deb "$DEB/libd/libdecor-0/libdecor-0-0_0.2.2-2_arm64.deb"
fetch_deb "$DEB/i/icu/libicu76_76.1-4_arm64.deb"

echo "==> Installing them into the glibc tree"
cp -P "$WORK"/usr/lib/aarch64-linux-gnu/libSDL2-2.0.so.0* "$PREFIX/glibc/lib/"
cp -P "$WORK"/usr/lib/aarch64-linux-gnu/libsamplerate.so.0* "$PREFIX/glibc/lib/"
cp -P "$WORK"/usr/lib/aarch64-linux-gnu/libdecor-0.so.0* "$PREFIX/glibc/lib/"
cp -P "$WORK"/usr/lib/aarch64-linux-gnu/libicu*.so.76* "$PREFIX/glibc/lib/"

# The .deb files ship the real libraries; make sure the soname symlinks
# point at them, since cp -P only preserves links that were in the archive.
cd "$PREFIX/glibc/lib"
for base in libSDL2-2.0.so.0 libsamplerate.so.0 libdecor-0.so.0; do
    real=$(ls "$base".* 2>/dev/null | head -1)
    [ -n "$real" ] && [ ! -e "$base" ] && ln -sf "$real" "$base"
done
for icu in libicudata libicui18n libicuio libicutest libicutu libicuuc; do
    real=$(ls "$icu.so.76."* 2>/dev/null | head -1)
    [ -n "$real" ] && [ ! -e "$icu.so.76" ] && ln -sf "$real" "$icu.so.76"
done

echo "==> Extracting the GOG installer"
mkdir -p "$DEST/game"
unzip -o "$INSTALLER" -d "$DEST/game" || true

GAMEDIR="$DEST/game/data/noarch/game/linux"
[ -f "$GAMEDIR/starbound" ] || { echo "starbound binary not found after extracting."; exit 1; }
chmod +x "$GAMEDIR/starbound"

echo "==> Building the /tmp redirect shim (x86_64)"
mkdir -p "$PREFIX/glibc/tmp"
cat > "$DEST/tmp_redirect.c" << 'CEOF'
/* Redirect /tmp writes to a directory Android actually allows.
   No libc headers: this is built for x86_64 on an ARM host, so we
   declare the few functions we need ourselves. */
typedef unsigned long size_t;

extern void *dlsym(void *handle, const char *symbol);
#define RTLD_NEXT ((void *) -1L)

extern int strncmp(const char *s1, const char *s2, size_t n);
extern size_t strlen(const char *s);
extern int snprintf(char *str, size_t size, const char *format, ...);

#define NEW_TMP_DIR "/data/data/com.termux/files/usr/glibc/tmp"

static char redirect_buf[512];

typedef int (*mkstemp_t)(char *);
typedef int (*unlink_t)(const char *);
typedef int (*remove_t)(const char *);

int mkstemp(char *tmpl) {
    static mkstemp_t real_mkstemp = 0;
    if (!real_mkstemp) real_mkstemp = (mkstemp_t)dlsym(RTLD_NEXT, "mkstemp");

    if (tmpl && strncmp(tmpl, "/tmp", 4) == 0 && (tmpl[4] == '/' || tmpl[4] == 0)) {
        char local[512];
        snprintf(local, sizeof(local), "%s%s", NEW_TMP_DIR, tmpl + 4);
        int fd = real_mkstemp(local);
        size_t needed = strlen(local);
        size_t avail = strlen(tmpl);
        if (needed <= avail) {
            size_t i = 0;
            while (local[i]) { tmpl[i] = local[i]; i++; }
            tmpl[i] = 0;
        }
        snprintf(redirect_buf, sizeof(redirect_buf), "%s", local);
        return fd;
    }
    return real_mkstemp(tmpl);
}

int unlink(const char *pathname) {
    static unlink_t real_unlink = 0;
    if (!real_unlink) real_unlink = (unlink_t)dlsym(RTLD_NEXT, "unlink");
    if (pathname && strncmp(pathname, "/tmp", 4) == 0 && (pathname[4] == '/' || pathname[4] == 0))
        return real_unlink(redirect_buf);
    return real_unlink(pathname);
}

int remove(const char *pathname) {
    static remove_t real_remove = 0;
    if (!real_remove) real_remove = (remove_t)dlsym(RTLD_NEXT, "remove");
    if (pathname && strncmp(pathname, "/tmp", 4) == 0 && (pathname[4] == '/' || pathname[4] == 0))
        return real_remove(redirect_buf);
    return real_remove(pathname);
}
CEOF

clang --target=x86_64-linux-gnu -shared -fPIC -nostdlib \
    -o "$DEST/tmp_redirect_x64.so" "$DEST/tmp_redirect.c"

echo "==> Writing launcher"
cat > "$DEST/run.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Starbound - x86_64 under box64, with a /tmp redirect shim preloaded.
G="/data/data/com.termux/files/usr/glibc"
D="$HOME/games/starbound"

glibc-runner --shell "pulseaudio-start >/dev/null 2>&1; \
export DISPLAY=:0; \
export VK_ICD_FILENAMES=$G/share/vulkan/icd.d/freedreno_icd.aarch64.json; \
export TU_DEBUG=noconform; \
export SDL_AUDIODRIVER=pulseaudio; \
export PULSE_SERVER=127.0.0.1; \
export BOX64_LD_PRELOAD=$D/tmp_redirect_x64.so; \
export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:.; \
cd '$D/game/data/noarch/game/linux'; \
box64 ./starbound"
EOF
chmod +x "$DEST/run.sh"

echo "==> Cleaning up"
rm -rf "$WORK"

cat << 'EOF'

Starbound installed to ~/games/starbound

Start Termux:X11, then run:
  ~/games/starbound/run.sh

Mods go in game/data/noarch/game/mods/ - .pak files are picked up
directly, .zip and .rar archives are ignored and need extracting first.
EOF
