#!/usr/bin/env bash

set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
source "$root/scripts/runtime-common.sh"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
mkdir -p "$temporary/src/pl/plpython"
path="$temporary/src/pl/plpython/plpy_main.c"
printf '\tPy_Initialize();\n' > "$path"
printf '{"version":"18.6","commit":"preserved"}\n' > "$temporary/source-input.json"
before=$(runtime_sha256 "$path")
bash "$root/scripts/relocate-plpython.sh" "$temporary"
jq -e --arg before "$before" --arg after "$(runtime_sha256 "$path")" \
    '.commit == "preserved" and (.packaging_patches[0] |
       .before_sha256 == $before and .after_sha256 == $after and $before != $after and
       .script == "relocate-plpython.sh")' "$temporary/source-input.json" >/dev/null
grep -Fq 'getenv("PYTHONHOME")' "$path"
if bash "$root/scripts/relocate-plpython.sh" "$temporary" > /dev/null 2>&1; then exit 1; fi
# No record or source changes on rejection, and PostgreSQL 14 remains unpatched.
jq '.version = "14.24"' "$temporary/source-input.json" > "$temporary/metadata"
mv "$temporary/metadata" "$temporary/source-input.json"
cp "$temporary/source-input.json" "$temporary/before.json"
bash "$root/scripts/relocate-plpython.sh" "$temporary"
cmp "$temporary/before.json" "$temporary/source-input.json"
echo 'PL/Python relocation patch, digests, repeat rejection and PostgreSQL 14 checks passed'
