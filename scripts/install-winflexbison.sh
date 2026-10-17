#!/usr/bin/env bash

set -euo pipefail
destination="${1:?Usage: install-winflexbison.sh <destination>}"
script_directory=$(cd "$(dirname "$0")" && pwd)
source "$script_directory/build-diagnostics.sh"

# Same upstream archive as Chocolatey winflexbison3 2.5.24.20210105. Keep the
# version fixed while removing the additional Chocolatey download dependency.
version=2.5.24
archive_name="win_flex_bison-$version.zip"
sha256=39c6086ce211d5415500acc5ed2d8939861ca1696aee48909c7f6daf5122b505
test ! -e "$destination"
test ! -L "$destination"
mkdir -p "$(dirname "$destination")"
temporary=$(mktemp -d "${destination}.download.XXXXXX")
trap 'rm -rf "$temporary"' EXIT

build_phase "Download WinFlexBison $version"
curl --fail --location --silent --show-error --retry 3 --retry-connrefused \
    --retry-max-time 180 --connect-timeout 20 --max-time 60 \
    --proto '=https' --proto-redir '=https' \
    "https://github.com/lexxmark/winflexbison/releases/download/v$version/$archive_name" \
    --output "$temporary/$archive_name"
printf '%s  %s\n' "$sha256" "$archive_name" > "$temporary/checksum"
"$script_directory/verify-checksum.sh" "$temporary/$archive_name" "$temporary/checksum"

# Publish the directory only after checksum verification and full extraction.
python -m zipfile -e "$temporary/$archive_name" "$temporary/install"
test -f "$temporary/install/win_flex.exe"
test -f "$temporary/install/win_bison.exe"
mv "$temporary/install" "$destination"
