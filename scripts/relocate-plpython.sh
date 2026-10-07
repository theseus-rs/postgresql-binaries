#!/usr/bin/env bash

set -euo pipefail
script_directory=$(cd "$(dirname "$0")" && pwd)
source "$script_directory/runtime-common.sh"
source_directory=${1:?Usage: relocate-plpython.sh <source_directory>}
record="$source_directory/source-input.json"
major=$(jq -er '.version | split(".")[0] | tonumber' "$record")
[ "$major" -ge 15 ] || exit 0
path="$source_directory/src/pl/plpython/plpy_main.c"
needle=$'\tPy_Initialize();'
if [ "$(grep -Fxc "$needle" "$path" || true)" != 1 ] || grep -Fq 'getenv("PYTHONHOME")' "$path"; then
    runtime_die 'Expected exactly one unpatched PL/Python initialization'
fi
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
cat > "$temporary/initialize" <<'C'
	if (getenv("PYTHONHOME") == NULL)
	{
		char python_home[MAXPGPATH];

		/* Python 3.11 cannot discover an embedded executable on Linux. */
		strlcpy(python_home, my_exec_path, sizeof(python_home));
		get_parent_directory(python_home);
		get_parent_directory(python_home);
		if (setenv("PYTHONHOME", python_home, 0) != 0)
			ereport(FATAL, (errmsg("could not set bundled Python home: %m")));
	}
	Py_Initialize();
C
before=$(runtime_sha256 "$path")
awk -v replacement="$temporary/initialize" '
    $0 == "\tPy_Initialize();" {
        while ((getline line < replacement) > 0) print line
        close(replacement)
        next
    }
    { print }
' "$path" > "$temporary/patched"
after=$(runtime_sha256 "$temporary/patched")
jq --arg before "$before" --arg after "$after" \
    --arg script_sha256 "$(runtime_sha256 "$0")" '
    .packaging_patches = [{script: "relocate-plpython.sh", script_sha256: $script_sha256,
        file: "src/pl/plpython/plpy_main.c", before_sha256: $before, after_sha256: $after}]
' "$record" > "$temporary/record"
cat "$temporary/patched" > "$path"
cat "$temporary/record" > "$record"
