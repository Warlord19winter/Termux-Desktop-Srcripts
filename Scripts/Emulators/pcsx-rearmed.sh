#!/data/data/com.termux/files/usr/bin/bash
# PCSX-ReARMed - PlayStation 1
#
# A native Termux package. Its dynarec targets AArch64 directly and HLE
# BIOS means no BIOS image is needed, so there is nothing to work around
# here - no box64, no glibc bridge.

set -eu

DEST="$HOME/games/pcsx-rearmed"

echo "==> Installing PCSX-ReARMed"
pkg install -y pcsx-rearmed pulseaudio

echo "==> Writing launcher"
mkdir -p "$DEST" "$HOME/games/roms/ps1"
cat > "$DEST/run.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# PCSX-ReARMed (PS1) - native Termux package, aarch64.
# Software GPU plugin: no upscaling, but bypasses the graphics stack.
# "NI 00001770 @..." lines are harmless (unimplemented rare opcodes).
# Usage:  run.sh                  -> menu
#         run.sh /path/game.cue   -> boot a game  (prefer .cue over .bin)

pulseaudio-start >/dev/null 2>&1
export DISPLAY="${DISPLAY:-:0}"
export SDL_AUDIODRIVER=pulseaudio
export PULSE_SERVER=127.0.0.1

if [ $# -gt 0 ]; then exec pcsx -cdfile "$1"; else exec pcsx; fi
EOF
chmod +x "$DEST/run.sh"

cat << 'EOF'

PCSX-ReARMed installed.

Put your games in ~/games/roms/ps1/ and run:
  ~/games/pcsx-rearmed/run.sh                       menu
  ~/games/pcsx-rearmed/run.sh ~/games/roms/ps1/game.cue

Prefer .cue files over .bin - the .cue describes the track layout.
No BIOS image needed; it uses HLE BIOS.
EOF
