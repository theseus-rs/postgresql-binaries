#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C
asset="${1:?Usage: verify-checksum.sh <asset> <checksum>}"
checksum="${2:?Missing checksum file}"
root=$(cd "$(dirname "$0")/.." && pwd)

record=
record_bytes=0
if IFS= read -r record < "$checksum"; then
    record_bytes=1 # Include the newline consumed by read.
fi
record_bytes=$((record_bytes + ${#record}))
checksum_bytes=$(wc -c < "$checksum")
# Reject extra lines and NUL bytes, which Bash may discard when reading.
if [ "$checksum_bytes" -ne "$record_bytes" ]; then
    echo "Invalid checksum record for ${asset##*/}" >&2
    exit 1
fi
record="${record%$'\r'}"
expected=$("$root/scripts/checksum.sh" "$asset")
if [ "$record" != "$expected" ]; then
    echo "Checksum or filename mismatch: ${asset##*/}" >&2
    exit 1
fi
printf '%s\n' "$expected"
