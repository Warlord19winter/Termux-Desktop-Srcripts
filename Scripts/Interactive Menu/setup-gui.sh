#!/data/data/com.termux/files/usr/bin/bash
# A tappable version of setup.sh - pick what to INSTALL.
#
# This is not the same as play-gui.sh: that one launches things you have
# already installed. This one installs them in the first place.
#
# Needs the desktop running, since it uses yad. If you have no desktop yet,
# use the terminal menu instead:  bash setup.sh

set -u

API="https://api.github.com/repos/Warlord19winter/Termux-Desktop-Srcripts/contents/Scripts"
REPO="https://raw.githubusercontent.com/Warlord19winter/Termux-Desktop-Srcripts/main/Scripts"
CACHE="$HOME/.cache/termux-desktop"

export DISPLAY="${DISPLAY:-:0}"

urlenc() { printf '%s' "$1" | sed 's/ /%20/g'; }

list_category() {
    curl -fsSL "$API/$(urlenc "$1")" 2>/dev/null \
        | grep '"name"' | cut -d'"' -f4 | grep '\.sh$' | sed 's/\.sh$//'
}

while true; do
    cat=$(printf 'Desktop\nEmulators\nGames\nPrograms\n' | yad \
        --list --title="Install" --width=320 --height=300 \
        --column="Category" \
        --text="What would you like to install?" \
        --button="Quit:1" --button="Choose:0" --separator="")
    [ $? -eq 0 ] || exit 0
    [ -n "$cat" ] || continue

    items=$(list_category "$cat")
    if [ -z "$items" ]; then
        yad --info --title="$cat" --text="Nothing in $cat yet." --button="OK:0"
        continue
    fi

    pick=$(printf '%s\n' "$items" | yad \
        --list --title="$cat" --width=320 --height=420 \
        --column="Available" \
        --text="Select one to install." \
        --button="Back:1" --button="Install:0" --separator="")
    [ $? -eq 0 ] || continue
    [ -n "$pick" ] || continue

    mkdir -p "$CACHE"
    if curl -fsSL "$REPO/$(urlenc "$cat")/$pick.sh" -o "$CACHE/$pick.sh"; then
        # Installs can take hours, so run them in a terminal where the
        # output is visible rather than hiding it behind a progress bar.
        xfce4-terminal --title="Installing $pick" \
            --command="bash -c 'bash \"$CACHE/$pick.sh\"; echo; echo Press enter to close; read'" \
            2>/dev/null || bash "$CACHE/$pick.sh"
    else
        yad --error --text="Could not fetch $cat/$pick.sh" --button="OK:0"
    fi
done
