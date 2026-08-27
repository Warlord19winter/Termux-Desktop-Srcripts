#!/data/data/com.termux/files/usr/bin/bash
# Prism Launcher - Minecraft
#
# Built from source against Termux's own Qt6. This is a long build.
#
# WHY NOT THE OFFICIAL APPIMAGE:
#   The prebuilt Linux binaries cannot work here. Their bundled Qt uses
#   QSaveFile, which materialises its atomic temp file with linkat() - and
#   Android denies hard links everywhere in app storage. Every config save
#   and cache write fails, so the launcher cannot keep an account or manage
#   instances. Termux's own Qt6 is patched around this, so a source build
#   works. The AppImage also dies with SIGSYS from its static sharun shim,
#   and bundles no OpenSSL at all.
#
# THREE PATCHES, applied from prism-termux.patch:
#   * install(TARGETS ... RUNTIME_DEPENDENCY_SET) - CMake refuses this when
#     the system is "Android". It only bundles dependencies for packaging,
#     so it is removed.
#   * Java -source/-target 7 raised to 8. JDK 25 dropped support for 7.
#   * gamemode guards. Termux's Qt reports Q_OS_LINUX because it IS a Linux
#     build, while Termux's CMake reports Android - so CMake skips the
#     gamemode dependency while the source still includes its header. The
#     guards are changed to LAUNCHER_USE_GAMEMODE, which is never defined.
#
# tomlplusplus is not packaged for Termux, so it is built here too. It is
# header-only, so that part is quick.
#
# Minecraft itself needs a Java runtime; Termux's OpenJDK 21 works for
# current versions. Older Minecraft may want an older JDK.

set -eu

COMMIT="d7870ff659cbb66707fe0141e21e28bf84210857"
SRC="$HOME/build/PrismLauncher"
TOML_SRC="$HOME/build/tomlplusplus"
DEST="$HOME/games"
JOBS="${JOBS:-4}"
PATCH_URL="https://raw.githubusercontent.com/Warlord19winter/Termux-Desktop-Srcripts/main/Scripts/Games/prism-termux.patch"

echo "==> Installing build dependencies"
pkg install -y git cmake ninja clang extra-cmake-modules
pkg install -y qt6-qtbase qt6-qtnetworkauth qt6-qtsvg qt6-qttools
pkg install -y qt6-qtbase-gtk-platformtheme
pkg install -y cmark libarchive vulkan-headers zlib
pkg install -y openjdk-21 openjdk-21-x

echo "==> Building tomlplusplus (header-only, not packaged for Termux)"
rm -rf "$TOML_SRC"
git clone --depth 1 --branch v3.4.0 https://github.com/marzer/tomlplusplus "$TOML_SRC"
cmake -S "$TOML_SRC" -B "$TOML_SRC/build" -G Ninja \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release
cmake --install "$TOML_SRC/build"

echo "==> Cloning Prism Launcher at $COMMIT"
rm -rf "$SRC"
git clone https://github.com/PrismLauncher/PrismLauncher "$SRC"
cd "$SRC"
git checkout "$COMMIT"
git submodule update --init --recursive

echo "==> Applying the Termux patch"
mkdir -p "$HOME/.cache"
PATCH_FILE="$HOME/.cache/prism-termux.patch"
curl -fL "$PATCH_URL" -o "$PATCH_FILE"
git apply "$PATCH_FILE"

echo "==> Configuring"
cmake -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$HOME/games/prism-built" \
    -DENABLE_LTO=OFF \
    -DLauncher_ENABLE_JAVA_DOWNLOADER=OFF \
    -DLauncher_QT_VERSION_MAJOR=6

echo "==> Building (this takes a while)"
cmake --build build -j"$JOBS"

echo "==> Writing launcher"
mkdir -p "$DEST"
cat > "$DEST/prism-run.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Prism Launcher (Minecraft) - built from source against Termux's Qt6.
# Start Termux:X11 before running.
export DISPLAY=:0
exec "$HOME/build/PrismLauncher/build/prismlauncher" "$@"
EOF
chmod +x "$DEST/prism-run.sh"

cat << 'EOF'

Prism Launcher built.

Start Termux:X11, then run:
  ~/games/prism-run.sh

On first run it will ask for a Java runtime - point it at
  $PREFIX/lib/jvm/java-21-openjdk

You will need a Minecraft account to play online.

Note the build tree in ~/build/PrismLauncher is where the binary lives;
do not delete it.
EOF
