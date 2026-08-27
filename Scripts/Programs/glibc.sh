#!/data/data/com.termux/files/usr/bin/bash
# The glibc bridge and box64
#
# Termux uses Bionic, Android's libc. Most Linux binaries expect glibc, so
# anything you did not build yourself needs a glibc userland to run
# against. glibc-runner provides one at $PREFIX/glibc, and `grun` launches
# programs into it.
#
# box64 is separate: it translates x86_64 instructions to ARM64 at
# runtime, for binaries that were never built for ARM at all. The two are
# often used together - an x86_64 Linux binary needs box64 for the
# instructions and the glibc bridge for the libraries.
#
# This costs around 2 GB of disk. Several scripts here depend on it:
# xemu, DuckStation, PCSX2, RetroArch, Factorio, Starbound and OpenMW.
#
# Anything built natively for Bionic - RPCS3, Vita3K, PPSSPP, mGBA,
# PCSX-ReARMed - does not need any of this and runs faster without it.

set -eu

echo "==> Adding the glibc repository"
pkg install -y glibc-repo

echo "==> Installing the glibc bridge"
pkg install -y glibc-runner

echo "==> Installing box64"
pkg install -y box64-glibc

echo "==> Installing the graphics and audio libraries most games want"
pkg install -y mesa-glibc mesa-vulkan-icd-freedreno-glibc vulkan-icd-loader-glibc
pkg install -y pulseaudio-glibc libx11-glibc libxext-glibc

cat << 'EOF'

Installed.

  grun <program>          run a glibc binary
  grun box64 <program>    run an x86_64 binary

Check it works:
  grun box64 --version

Note this pulls in a large dependency tree - around 2 GB once the
libraries the games need are in. Check with:
  du -sh $PREFIX/glibc
EOF
