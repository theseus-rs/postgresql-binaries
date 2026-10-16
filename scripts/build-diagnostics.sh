#!/usr/bin/env bash

# Source from build scripts using errexit. Keep diagnostics on stderr so command
# substitutions and generated metadata are not polluted. No environment dump or
# expanded command arguments: BASH_COMMAND contains the source command text.
build_phase() { printf '[build] %s\n' "$*" >&2; }

build_error() {
    local status=$1 file=$2 line=$3 command=$4 pipeline=$5
    printf 'Build failed: %s:%s: %s (exit %s; pipeline statuses: %s)\n' \
        "$file" "$line" "$command" "$status" "$pipeline" >&2
    exit "$status"
}

# Inherit ERR in functions, subshells and command substitutions. Child scripts
# must source this helper themselves; existing EXIT cleanup traps stay intact.
set -E
trap 'build_error "$?" "${BASH_SOURCE[0]}" "$LINENO" "$BASH_COMMAND" "${PIPESTATUS[*]}"' ERR
