#!/usr/bin/env bash

# Debian 12's patchelf 0.14.3 corrupts the MIPS postgres executable when its
# RUNPATH grows. Build the fixed release for MIPS; upstream has no MIPS binary.
set -euo pipefail
version=0.19.1
sha256=491108728f120ce05b539934b41a750235031a6df8abc6b47e57aff7de15094d
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
archive="$temporary/patchelf.tar.gz"
wget --https-only --tries=3 --timeout=30 \
    "https://github.com/NixOS/patchelf/releases/download/$version/patchelf-$version.tar.gz" \
    -O "$archive"
printf '%s  %s\n' "$sha256" "$archive" | sha256sum --check --strict -
mkdir "$temporary/source"
tar xzf "$archive" --strip-components=1 -C "$temporary/source"
cd "$temporary/source"
./configure --prefix=/usr/local
make -j2
make install
test "$(/usr/local/bin/patchelf --version)" = "patchelf $version"
