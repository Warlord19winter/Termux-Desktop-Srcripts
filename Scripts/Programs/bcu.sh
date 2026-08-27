#!/data/data/com.termux/files/usr/bin/bash
# BCU - Battle Cats Ultimate
#
# A Java desktop app for browsing and simulating Battle Cats data. It runs
# on Termux's own OpenJDK - no glibc bridge needed.
#
# Two things it needs:
#   * libxtst, because AWT wants libXtst.so.6
#   * a writable java.io.tmpdir, because Java's ImageIO writes temp files
#     and Android denies /tmp
#
# BCU is distributed through its own Discord and Google Drive rather than a
# stable download URL, so you supply the jar yourself.

set -eu

DEST="$HOME/games/bcu"

echo "==> Installing Java and AWT dependencies"
pkg install -y openjdk-21 openjdk-21-x
pkg install -y libxtst

echo "==> Creating $DEST"
mkdir -p "$DEST" "$HOME/.cache/bcutmp"

echo "==> Writing launcher"
cat > "$DEST/run.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Battle Cats Ultimate - Java app on Termux's own OpenJDK.
# Put the BCU jar in this directory; the launcher finds it by name.
cd "$(dirname "$0")"
export DISPLAY=:0
mkdir -p "$HOME/.cache/bcutmp"

JAR=$(ls BCU*.jar 2>/dev/null | head -1)
if [ -z "$JAR" ]; then
    echo "No BCU jar found in $(pwd)"
    echo "Download it from the BCU Discord and put the .jar here."
    exit 1
fi

exec java -Djava.io.tmpdir="$HOME/.cache/bcutmp" -jar "$JAR"
EOF
chmod +x "$DEST/run.sh"

cat << 'EOF'

BCU set up at ~/games/bcu

You need to supply the jar yourself - BCU is distributed through its
Discord server rather than a stable download link. Put the .jar file in
~/games/bcu/ and the launcher will find it.

Start Termux:X11, then run:
  ~/games/bcu/run.sh
EOF
