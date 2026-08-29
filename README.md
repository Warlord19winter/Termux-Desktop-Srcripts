# Termux Desktop Scripts

# Desktop, Game, Code and 3d editing environment

Install scripts for running a Linux desktop, emulators and games inside
Termux on Android — no root, no proot, no chroot.

Everything here was built and tested on a Snapdragon 8 Gen 3 device
(Adreno 750) using the Turnip Vulkan driver. Other Adreno hardware should
work. Mali is untested.

## Quick start

```
pkg update && pkg install curl
curl -fsSL https://raw.githubusercontent.com/Warlord19winter/Termux-Desktop-Srcripts/main/setup.sh -o setup.sh
bash setup.sh
```

That opens an interactive menu. Start with **Desktop → xfce**, since
almost everything else needs X11.

You will also need the
[Termux:X11 app](https://github.com/termux/termux-x11/releases), which is
installed as an APK rather than a package.

## The two menus

They are easy to confuse:

- **`setup.sh`** and **`setup-gui.sh`** pick what to **install**.
- **`play.sh`** and **`play-gui.sh`** pick what to **run**, from what you
  already have installed.

Install the launchers with `install Programs launcher`, and the graphical
installer menu with `install Programs setup-gui`.

The `-gui` versions need the desktop running. The plain ones work from a
bare Termux prompt.

## Direct install

```
bash setup.sh install Emulators duckstation
bash setup.sh list Games
```

Some scripts need a path — the ones for games you own:

```
bash setup.sh install Games factorio ~/storage/downloads/factorio_installer.sh
```

## What's here

**Desktop** — XFCE on Termux:X11, with Mesa and the Turnip Vulkan driver.

**Emulators**

| Script | System |
|---|---|
| `duckstation` | PlayStation 1 |
| `pcsx-rearmed` | PlayStation 1 |
| `pcsx2` | PlayStation 2 |
| `ppsspp` | PSP |
| `vita3k` | PS Vita |
| `rpcs3` | PlayStation 3 |
| `xemu` | Original Xbox |
| `mgba` | GBA / GB / GBC |
| `o2em` | Magnavox Odyssey 2 |
| `retroarch` | many, via cores |

**Games** — Factorio, Terraria, Starbound, Vintage Story, Morrowind via
OpenMW, Mindustry, doom3 via Dhewm3, OpenRA, Minecraft via Prism Launcher.

**Programs** — Blender, BCU, the launchers, the graphical installer menu.

## You supply your own game files

Nothing here includes copyrighted material. Emulators need their own BIOS
or firmware images, and the commercial games need installers from GOG,
Steam or wherever you bought them. Each script says what it needs and
where it goes.

## How things run

Three different approaches appear here, and the script headers say which
applies:

- **Native ARM64.** Best case — the emulator's recompiler targets AArch64
  directly and rendering goes straight to Turnip. DuckStation, PPSSPP,
  Vita3K, RPCS3 and mGBA work this way.
- **glibc bridge.** The binary is ARM64 but linked against glibc, which
  Termux does not use. `glibc-runner` supplies one. xemu and DuckStation's
  AppImage need this.
- **box64.** The binary is x86_64 and gets translated at runtime. Slower,
  and for emulators it means a recompiler inside a recompiler. PCSX2,
  Factorio, Starbound, OpenMW and RetroArch run this way.

## Building from source

RPCS3, Vita3K and Prism Launcher are built from source and take hours.
Their headers explain what needed patching and why — that reasoning is
usually more useful than the script itself if you are adapting this to
another device.

The patches are kept as `.patch` files next to each script, against a
pinned upstream commit. If upstream has moved on, the patch may need
rebasing.

## Known rough edges

- Audio generally needs PulseAudio rather than ALSA; ALSA cannot find a
  card under Termux. Most launchers handle this, but xemu needs the
  socket path passed explicitly.
- Controllers are unreliable across the board — SDL's joystick subsystem
  wants udev, which Android does not expose.
- Turnip has no vendor-specific workarounds in most emulators, so expect
  graphical glitches in RPCS3 in particular.
