#!/data/data/com.termux/files/usr/bin/bash
# Termux Desktop Scripts
#
#   bash setup.sh install <category> <name>
#   bash setup.sh list <category>
#
# Categories: Desktop, Emulators, Games, Programs

set -eu

REPO="https://raw.githubusercontent.com/Warlord19winter/Termux-Desktop-Srcripts/main/Scripts"
API="https://api.github.com/repos/Warlord19winter/Termux-Desktop-Srcripts/contents/Scripts"
CACHE="$HOME/.cache/termux-desktop"

usage() {
    printf "Usage:\n"
    printf "  %s install <category> <name>\n" "$(basename "$0")"
    printf "  %s list <category>\n\n" "$(basename "$0")"
    printf "Categories: Desktop, Emulators, Games, Programs\n"
}

list_category() {
    curl -fsSL "$API/$1" | grep '"name"' | cut -d'"' -f4 | grep '\.sh$' || true
}

install_script() {
    local cat="$1" name="$2"
    mkdir -p "$CACHE"
    printf "Fetching %s/%s.sh\n" "$cat" "$name"
    if curl -fsSL "$REPO/$cat/$name.sh" -o "$CACHE/$name.sh"; then
        bash "$CACHE/$name.sh"
    else
        printf "Not found: %s/%s.sh\n" "$cat" "$name"
        return 1
    fi
}

case "${1:-}" in
    install) [ $# -eq 3 ] && install_script "$2" "$3" || usage ;;
    list)    [ $# -eq 2 ] && list_category "$2" || usage ;;
    *)       usage ;;
esac
