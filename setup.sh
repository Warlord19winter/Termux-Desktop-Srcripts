#!/data/data/com.termux/files/usr/bin/bash
# Termux Desktop Scripts
#
#   bash setup.sh                        interactive menu
#   bash setup.sh install <cat> <name>   install one thing directly
#   bash setup.sh list <cat>             list what a category holds
#
# Categories: Desktop, Emulators, Games, Programs

set -eu

REPO="https://raw.githubusercontent.com/Warlord19winter/Termux-Desktop-Srcripts/main/Scripts"
API="https://api.github.com/repos/Warlord19winter/Termux-Desktop-Srcripts/contents/Scripts"
CACHE="$HOME/.cache/termux-desktop"
CATEGORIES="Desktop Emulators Games Programs"

if [ -t 1 ]; then
    R='\033[0m'; B='\033[1m'; DIM='\033[2m'
    GRN='\033[1;32m'; CYN='\033[1;36m'; RED='\033[1;31m'
else
    R=''; B=''; DIM=''; GRN=''; CYN=''; RED=''
fi

usage() {
    printf "Usage:\n"
    printf "  %s                        interactive menu\n" "$(basename "$0")"
    printf "  %s install <cat> <name> [args...]\n" "$(basename "$0")"
    printf "      install directly; some scripts take a path, e.g.\n"
    printf "      install Games factorio ~/storage/downloads/factorio.sh\n"
    printf "  %s list <cat>             list a category\n\n" "$(basename "$0")"
    printf "Categories: %s\n" "$CATEGORIES"
}

list_category() {
    curl -fsSL "$API/$1" 2>/dev/null | grep '"name"' | cut -d'"' -f4 \
        | grep '\.sh$' | sed 's/\.sh$//' || true
}

install_script() {
    local cat="$1" name="$2"
    shift 2
    mkdir -p "$CACHE"
    printf "\n${CYN}Fetching %s/%s${R}\n" "$cat" "$name"
    if curl -fsSL "$REPO/$cat/$name.sh" -o "$CACHE/$name.sh"; then
        bash "$CACHE/$name.sh" "$@"
    else
        printf "${RED}Not found: %s/%s.sh${R}\n" "$cat" "$name"
        return 1
    fi
}

menu() {
    while true; do
        printf "\n${B}Termux Desktop Scripts${R}\n\n"
        local i=1
        for c in $CATEGORIES; do
            printf "  ${GRN}%d${R}) %s\n" "$i" "$c"
            i=$((i+1))
        done
        printf "\n  ${DIM}q) quit${R}\n\n"
        printf "Category: "
        read -r choice

        case "$choice" in
            q|Q|quit|exit) printf "\n"; return 0 ;;
            '') continue ;;
        esac

        local cat=""
        i=1
        for c in $CATEGORIES; do
            [ "$choice" = "$i" ] && cat="$c"
            i=$((i+1))
        done
        [ -n "$cat" ] || { printf "${RED}Not a valid choice.${R}\n"; continue; }

        printf "\n${CYN}Fetching the list...${R}\n"
        local items
        items=$(list_category "$cat")
        [ -n "$items" ] || { printf "${DIM}Nothing in %s yet.${R}\n" "$cat"; continue; }

        printf "\n${B}%s${R}\n\n" "$cat"
        i=1
        for n in $items; do
            printf "  ${GRN}%d${R}) %s\n" "$i" "$n"
            i=$((i+1))
        done
        printf "\n  ${DIM}b) back${R}\n\n"
        printf "Install: "
        read -r pick

        case "$pick" in b|B|'') continue ;; esac

        local name=""
        i=1
        for n in $items; do
            [ "$pick" = "$i" ] && name="$n"
            i=$((i+1))
        done

        if [ -n "$name" ]; then
            install_script "$cat" "$name" || true
            printf "\n${DIM}Enter to continue...${R}"
            read -r _
        else
            printf "${RED}Not a valid choice.${R}\n"
        fi
    done
}

case "${1:-}" in
    '')      menu ;;
    install) [ $# -ge 3 ] && { shift; install_script "$@"; } || usage ;;
    list)    [ $# -eq 2 ] && list_category "$2" || usage ;;
    *)       usage ;;
esac
