#!/data/data/com.termux/files/usr/bin/bash
# GUI front end for play.sh. Reads the same game table, so there is
# only one place to add games. Start Termux:X11 before running.

export DISPLAY=:0

while true; do
    # Installed games only: lines between "Installed" and "Not installed",
    # formatted as "  N) Display Name   slug"
    rows=$(~/play.sh --list | awk '
        /^Installed/     { on=1; next }
        /^Not installed/ { on=0 }
        on && NF {
            slug = $NF
            $1 = ""; $NF = ""
            gsub(/^ +| +$/, "")
            print $0 "\n" slug
        }')

    [ -z "$rows" ] && { yad --error --text="No installed games found."; exit 1; }

    choice=$(printf '%s\n' "$rows" | yad \
        --list \
        --title="Games" \
        --width=420 --height=520 \
        --column="Game" --column="slug" \
        --hide-column=2 --print-column=2 \
        --button="Refresh:2" --button="Quit:1" --button="Play:0" \
        --separator="")

    case $? in
        0) [ -n "$choice" ] && ~/play.sh "$choice" ;;
        2) continue ;;
        *) exit 0 ;;
    esac
done
