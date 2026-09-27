#!/usr/bin/env bash

set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
mkdir "$temporary/bin"
cat > "$temporary/bin/git" <<'SH'
#!/bin/sh
echo called >> "$CALL_LOG"
exit 42
SH
chmod +x "$temporary/bin/git"
export CALL_LOG="$temporary/calls"
export PATH="$temporary/bin:$PATH"

if "$root/scripts/fetch-source.sh" 18.6 "$temporary/invalid"; then
    echo 'Malformed version accepted' >&2
    exit 1
fi
test ! -e "$CALL_LOG"
if "$root/scripts/fetch-source.sh" 18.6.0 "$temporary/source"; then
    echo 'Failed download accepted' >&2
    exit 1
fi
test "$(wc -l < "$CALL_LOG" | tr -d ' ')" = 1
test ! -e "$temporary/source/source-input.json"
echo 'Input rejection checks passed'
