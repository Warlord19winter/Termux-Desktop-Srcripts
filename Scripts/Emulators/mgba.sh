#!/data/data/com.termux/files/usr/bin/bash
# mGBA - Game Boy, Game Boy Color and Game Boy Advance
#
# Packaged for Termux as a native aarch64 build, so this is just a package
# install plus a launcher. No glibc bridge or box64 needed.

set -eu

DEST="$HOME/games/mgba"

echo "==> Installing mGBA"
pkg install -y mgba-qt

echo "==> Writing launcher"
mkdir -p "$DEST" "$HOME/games/roms/gba"
cat > "$DEST/run.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# mGBA (GBA/GB/GBC). Put ROMs in ~/games/roms/gba/
export DISPLAY=:0
exec mgba-qt "$@"
EOF
chmod +x "$DEST/run.sh"

cat << 'EOF'

mGBA installed.

Put your ROMs in ~/games/roms/gba/ and start it with:
  ~/games/mgba/run.sh

Or open a ROM directly:
  ~/games/mgba/run.sh ~/games/roms/gba/game.gba
EOF
