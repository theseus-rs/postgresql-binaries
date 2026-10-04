#!/usr/bin/env bash

set -euo pipefail
install_directory="${1:?Missing install directory}"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
data_files=(/usr/share/icu/*/icudt*.dat)
test "${#data_files[@]}" -eq 1
data="${data_files[0]}"
test -f "$data"
name=$(basename "$data" .dat)
entrypoint="${name%?}"
soname=$(patchelf --print-soname /usr/lib/libicudata.so)
mkdir -p "$install_directory/lib"
# Alpine's libicudata is only a stub: embed the full matching archive in a data
# library with the same entry point/SONAME, avoiding a fixed ICU_DATA directory.
genccode -a gcc -e "$entrypoint" -f icudata -d "$temporary" "$data"
read -r -a compile_flags <<< "${CFLAGS:--O2}"
cc "${compile_flags[@]}" -fPIC -shared -Wl,-soname,"$soname" \
    "$temporary/icudata.S" -o "$install_directory/lib/$soname"
script_directory=$(cd "$(dirname "$0")" && pwd)
source "$script_directory/runtime-common.sh"
jq -n --arg source "$data" --arg digest "$(runtime_sha256 "$data")" --arg soname "$soname" \
    '{source: $source, sha256: $digest, soname: $soname,
      generator: "ICU genccode and target C compiler",
      authentication: "installed from signed Alpine package repository"}' \
    > "$install_directory/icu-data-input.json"
