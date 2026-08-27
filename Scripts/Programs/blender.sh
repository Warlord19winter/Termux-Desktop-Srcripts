#!/data/data/com.termux/files/usr/bin/bash
# Blender 5.2
#
# From the TUR repository, native aarch64. Two things worth knowing:
#
#   * The plain "blender" package is an old 3.6 build linked against
#     Python 3.13, which Termux no longer ships - it will not start, and
#     the error ("library libpython3.13.so not found") looks nothing like
#     a packaging problem. Use blender-5.2.
#
#   * Blender needs OpenGL 4.3 or newer, which software rendering does not
#     provide. Mesa 26 selects Zink on Turnip automatically, so no driver
#     override is needed - but check the renderer if it refuses to start.

set -eu

DEST="$HOME/games/blender"

echo "==> Adding the TUR repository"
pkg install -y tur-repo

echo "==> Installing Blender 5.2"
pkg install -y blender5

echo "==> Writing launcher"
mkdir -p "$DEST"
cat > "$DEST/run.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Blender 5.2. The plain "blender" command is the stale 3.6 package,
# linked against a Python that Termux no longer ships - it will not run.
export DISPLAY=:0
exec blender-5.2 "$@"
EOF
chmod +x "$DEST/run.sh"

cat << 'EOF'

Blender 5.2 installed.

Start Termux:X11, then run:
  ~/games/blender/run.sh

If it complains about drivers, check what OpenGL you are getting:
  DISPLAY=:0 glxinfo -B | grep -E "renderer|OpenGL version"

You want "zink Vulkan ... (Turnip Adreno ...)" and OpenGL 4.6.
If it says llvmpipe you are on software rendering and Blender will
refuse to start.
EOF
