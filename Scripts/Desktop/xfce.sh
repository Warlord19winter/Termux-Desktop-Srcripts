#!/data/data/com.termux/files/usr/bin/bash
# XFCE desktop on Termux:X11, with Turnip/Zink hardware acceleration.
#
# Needs the Termux:X11 app installed separately from
# https://github.com/termux/termux-x11/releases

set -eu

echo "==> Adding the x11 repository"
pkg install -y x11-repo

echo "==> Installing XFCE and Termux:X11"
pkg install -y termux-x11-nightly xfce4 xfce4-terminal dbus

echo "==> Installing Mesa with Turnip (Adreno Vulkan)"
pkg install -y mesa mesa-vulkan-icd-freedreno vulkan-loader vulkan-tools

echo "==> Installing audio"
pkg install -y pulseaudio

echo "==> Writing ~/start-desktop.sh"
cat > "$HOME/start-desktop.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Start the XFCE desktop on Termux:X11.
#
# Open the Termux:X11 app FIRST, then run this. It blocks until you log out.

export DISPLAY=:0
export PULSE_SERVER=127.0.0.1
pulseaudio-start >/dev/null 2>&1

termux-x11 :0 -xstartup "dbus-launch --exit-with-session xfce4-session"
EOF
chmod +x "$HOME/start-desktop.sh"

cat << 'EOF'

XFCE installed.

Install the Termux:X11 app if you have not already:
  https://github.com/termux/termux-x11/releases

Then open that app first, and start the desktop with:
  ~/start-desktop.sh

Check acceleration once the desktop is up:
  glxinfo -B | grep renderer
Expect "zink Vulkan ... (Turnip Adreno ...)" - if it says llvmpipe,
you are on software rendering.
EOF
