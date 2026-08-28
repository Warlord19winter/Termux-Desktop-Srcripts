#!/data/data/com.termux/files/usr/bin/bash
# ============================================================================
#  play.sh - pick a game or program to launch
# ============================================================================
#
#  Scans for what's installed and shows a numbered menu. Anything not yet
#  installed is listed too, with the setup command needed to get it.
#
#  Detection is by launcher script: any executable run.sh under ~/games/*/
#  is picked up automatically, so games added later appear without editing
#  this file. The table below only supplies nice names and install hints.
#
#  Usage:
#      ./play.sh              interactive menu
#      ./play.sh factorio     launch directly by name
#      ./play.sh --list       print what's installed, no menu
#
#  Start Termux:X11 before launching anything graphical.
#
# ============================================================================

set -uo pipefail

GAMES_DIR="$HOME/games"

# --- colours (disabled when not a terminal) ---------------------------------
if [ -t 1 ]; then
    R='\033[0m'; B='\033[1m'; DIM='\033[2m'
    GRN='\033[1;32m'; YEL='\033[1;33m'; CYN='\033[1;36m'; MAG='\033[1;35m'
    RED='\033[1;31m'
else
    R=''; B=''; DIM=''; GRN=''; YEL=''; CYN=''; MAG=''; RED=''
fi

# ============================================================================
#  Known titles: key | display name | launcher path | install hint
# ============================================================================
#  Launcher path is relative to $HOME. Anything found under ~/games/*/run.sh
#  that isn't listed here still shows up, just with its directory name.

KNOWN="
factorio|Factorio|games/factorio/run.sh|bash setup.sh install Games factorio
vintagestory|Vintage Story|games/vintagestory/run.sh|bash setup.sh install Games vintagestory
terraria|Terraria|games/terraria/run.sh|bash setup.sh install Games terraria
starbound|Starbound|games/starbound/run.sh|bash setup.sh install Games starbound
openmw|Morrowind (OpenMW)|games/openmw/run.sh|bash setup.sh install Games openmw
retroarch|RetroArch|games/retroarch/run.sh|bash setup.sh install Emulators retroarch
mindustry|Mindustry|games/mindustry/run.sh|bash setup.sh install Games mindustry
tome|Tales of Maj'Eyal|games/tome/run.sh|bash setup.sh install Games tome
openra-ra|OpenRA: Red Alert|games/openra-ra/run.sh|bash setup.sh install Games openra-ra
openra-cnc|OpenRA: Tiberian Dawn|games/openra-cnc/run.sh|bash setup.sh install Games openra-cnc
openra-d2k|OpenRA: Dune 2000|games/openra-d2k/run.sh|bash setup.sh install Games openra-d2k
dhewm3|Doom 3 (dhewm3)|games/dhewm3/run.sh|bash setup.sh install Games dhewm3
blender|Blender 5.2|games/blender/run.sh|bash setup.sh install Programs blender
xemu|xemu (Original Xbox)|games/xemu/run.sh|bash setup.sh install Emulators xemu
pcsx2|PCSX2 (PS2)|games/pcsx2/run.sh|bash setup.sh install Emulators pcsx2
vita3k|Vita3K (PS Vita)|games/vita3k/run.sh|bash setup.sh install Emulators vita3k
o2em|O2EM2 (Odyssey 2)|games/o2em/run.sh|bash setup.sh install Emulators o2em
mgba|mGBA (GBA/GB/GBC)|games/mgba/run.sh|bash setup.sh install Emulators mgba
prism|Prism Launcher (Minecraft)|games/prism-run.sh|bash setup.sh install Games prism
bcu|Battle Cats Ultimate|games/bcu/run.sh|bash setup.sh install Programs bcu
duckstation|DuckStation (PS1)|games/duckstation/run.sh|bash setup.sh install Emulators duckstation
pcsx-rearmed|PCSX-ReARMed (PS1)|games/pcsx-rearmed/run.sh|bash setup.sh install Emulators pcsx-rearmed
ppsspp|PPSSPP (PSP)|games/ppsspp/run.sh|bash setup.sh install Emulators ppsspp
rpcs3-native|RPCS3 (PS3)|games/rpcs3-native/run.sh|bash setup.sh install Emulators rpcs3-native
"

# --- notes shown when a title is selected -----------------------------------
note_for() {
    case "$1" in
        mindustry)   echo "Loads slowly (~30s) - runs interpreted under box64." ;;
        tome)        echo "If the screen is white, check resolution.cfg vs xrandr." ;;
        openra-*)    echo "Startup is flaky - if it aborts, just run it again." ;;
        ppsspp)      echo "Don't press non-D-pad buttons in key mapping - segfaults." ;;
        rpcs3-native) echo "PS3. Turnip has no vendor workarounds - expect glitches." ;;
        bcu)         echo "Run BCU-Initializer.jar first if libs are missing." ;;
        prism)       echo "Set Java Executable to ~/jdk-glibc/java-glibc per instance." ;;
        *)           echo "" ;;
    esac
}

# ============================================================================
#  Build the list
# ============================================================================

declare -a KEYS NAMES PATHS INSTALLED NOTES
seen_paths=" "

add_entry() {   # key, name, abs_path, installed(0/1)
    KEYS+=("$1"); NAMES+=("$2"); PATHS+=("$3"); INSTALLED+=("$4")
    NOTES+=("$(note_for "$1")")
}

# known titles first, in listed order
while IFS='|' read -r key name relpath install; do
    [ -z "${key// }" ] && continue
    abs="$HOME/$relpath"
    if [ -x "$abs" ]; then
        add_entry "$key" "$name" "$abs" 1
        seen_paths="$seen_paths$abs "
    else
        add_entry "$key" "$name" "$install" 0
    fi
done <<< "$KNOWN"

# anything else with a run.sh that we didn't already list
if [ -d "$GAMES_DIR" ]; then
    while IFS= read -r f; do
        [ -x "$f" ] || continue
        case "$seen_paths" in *" $f "*) continue ;; esac
        d=$(basename "$(dirname "$f")")
        add_entry "$d" "$d" "$f" 1
    done < <(find "$GAMES_DIR" -maxdepth 2 -name "run.sh" 2>/dev/null | sort)
fi

count=${#KEYS[@]}
[ "$count" -gt 0 ] || { echo "Nothing found. Is ~/games populated?"; exit 1; }

# ============================================================================
#  Helpers
# ============================================================================

x11_running() { pgrep -f "termux-x11" >/dev/null 2>&1; }

launch() {   # index
    local i=$1
    local name="${NAMES[$i]}" path="${PATHS[$i]}" note="${NOTES[$i]}"

    if [ "${INSTALLED[$i]}" != "1" ]; then
        printf "\n${YEL}%s is not installed.${R}\n" "$name"
        printf "  Install with:\n    ${CYN}%s${R}\n\n" "$path"
        return 1
    fi

    if [ "${USE_X11:-0}" != "1" ] && ! x11_running; then
        printf "\n${YEL}Termux:X11 doesn't appear to be running.${R}\n"
        printf "  Start it, then try again. Launch anyway? [y/N] "
        read -r yn
        case "$yn" in [Yy]*) ;; *) return 1 ;; esac
    fi

    printf "\n${GRN}Launching %s...${R}\n" "$name"
    [ -n "$note" ] && printf "${DIM}  note: %s${R}\n" "$note"
    printf "\n"
    if [ "${USE_X11:-0}" = "1" ]; then
        # Start X11 with the game as the session; X11 exits with the game.
        termux-x11 :0 -xstartup "bash '$path'"
    else
        "$path"
    fi
    local rc=$?
    printf "\n${DIM}%s exited (code %d)${R}\n" "$name" "$rc"
    return 0
}

print_list() {
    printf "\n${B}Installed${R}\n"
    local any=0
    for i in $(seq 0 $((count-1))); do
        [ "${INSTALLED[$i]}" = "1" ] || continue
        printf "  ${GRN}%2d${R}) %-28s ${DIM}%s${R}\n" \
            "$((i+1))" "${NAMES[$i]}" "${KEYS[$i]}"
        any=1
    done
    [ "$any" = "1" ] || printf "  ${DIM}(none)${R}\n"

    local shown=0
    for i in $(seq 0 $((count-1))); do
        [ "${INSTALLED[$i]}" = "0" ] || continue
        [ "$shown" = "0" ] && printf "\n${B}Not installed${R}\n" && shown=1
        printf "  ${DIM}%2d) %-28s${R}\n" "$((i+1))" "${NAMES[$i]}"
    done
}

# ============================================================================
#  Direct launch by name:  ./play.sh factorio
# ============================================================================

if [ $# -gt 0 ]; then
    if [ "$1" = "--x11" ] || [ "$1" = "-x" ]; then
        USE_X11=1
        shift
    fi

    case "$1" in
        --list|-l)
            print_list; printf "\n"; exit 0 ;;
        --help|-h)
            printf "Usage: %s [--x11] [name|--list]\n" "$(basename "$0")"
            printf "  --x11   start Termux:X11 with the game as the session\n"
            exit 0 ;;
        *)
            for i in $(seq 0 $((count-1))); do
                if [ "${KEYS[$i]}" = "$1" ]; then launch "$i"; exit $?; fi
            done
            printf "${RED}Unknown: %s${R}\n" "$1"
            printf "Try: %s --list\n" "$(basename "$0")"
            exit 1 ;;
    esac
fi

# ============================================================================
#  Interactive menu
# ============================================================================

while true; do
    clear 2>/dev/null
    printf "${MAG}"
    printf "  ┌──────────────────────────────────────────┐\n"
    printf "  │           Termux Game Launcher           │\n"
    printf "  └──────────────────────────────────────────┘${R}\n"

    if x11_running; then
        printf "  ${GRN}●${R} Termux:X11 running\n"
    else
        printf "  ${YEL}○${R} Termux:X11 not detected\n"
    fi

    print_list

    printf "\n  ${DIM}q to quit${R}\n"
    printf "\n${B}Choose:${R} "
    if ! read -r choice; then printf "\n"; exit 0; fi   # EOF -> quit

    case "$choice" in
        q|Q|quit|exit) printf "\n"; exit 0 ;;
        '') continue ;;
        *[!0-9]*)
            # allow choosing by key name too
            found=0
            for i in $(seq 0 $((count-1))); do
                if [ "${KEYS[$i]}" = "$choice" ]; then
                    launch "$i"; found=1
                    printf "\n${DIM}Enter to continue...${R}"; read -r _
                    break
                fi
            done
            [ "$found" = "1" ] || { printf "\n${RED}Not a valid choice.${R}\n"; sleep 1; }
            ;;
        *)
            if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "$count" ]; then
                launch "$((choice-1))"
                printf "\n${DIM}Enter to continue...${R}"; read -r _
            else
                printf "\n${RED}Out of range.${R}\n"; sleep 1
            fi
            ;;
    esac
done
