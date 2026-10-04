#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C

# Read bytes from stdin so checksum tools never escape or reinterpret filenames.
for asset in "$@"; do
    name="${asset##*/}"
    case "$name" in
        ''|*\\*|*$'\r'*|*$'\n'*)
            echo "Unsupported checksum filename: $name" >&2
            exit 1
            ;;
    esac
    if command -v sha256sum > /dev/null 2>&1; then
        digest=$(sha256sum -b < "$asset")
    else
        digest=$(shasum -a 256 -b < "$asset")
    fi
    digest="${digest%% *}"
    if [[ ! "$digest" =~ ^[0-9a-f]{64}$ ]]; then
        echo "Invalid SHA-256 digest for $name" >&2
        exit 1
    fi
    printf '%s  %s\n' "$digest" "$name"
done
