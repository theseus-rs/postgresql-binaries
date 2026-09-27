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
cc ${CFLAGS:--O2} -fPIC -shared -Wl,-soname,"$soname" \
    "$temporary/icudata.S" -o "$install_directory/lib/$soname"
python3 - "$data" "$soname" "$install_directory" <<'PY'
import hashlib, json, pathlib, sys
data, soname, directory = sys.argv[1:]
with open(data, 'rb') as stream:
    digest = hashlib.file_digest(stream, 'sha256').hexdigest()
pathlib.Path(directory, 'icu-data-input.json').write_text(json.dumps({
    'source': data, 'sha256': digest, 'soname': soname,
    'generator': 'ICU genccode and target C compiler',
    'authentication': 'installed from signed Alpine package repository',
}, indent=2) + '\n')
PY
