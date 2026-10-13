#!/usr/bin/env bash

set -euo pipefail
asset="${1:?Usage: test-archive.sh <archive> <version>}"
version="${2:?Missing version}"
: "${TARGET:?Missing target}"
root=$(cd "$(dirname "$0")/.." && pwd)
"$root/scripts/verify-checksum.sh" "$asset" "$asset.sha256"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
archive="postgresql-$version-$TARGET"
# Windows builds select their interpreter through actions/setup-python.
if [[ "$TARGET" == *windows* ]]; then python_command=python; else python_command=python3; fi
"$python_command" "$root/scripts/verify-archive.py" "$asset" "$archive"
case "$asset" in
    *.tar.gz) tar xzf "$asset" -C "$temporary" ;;
    *.zip) unzip -q "$asset" -d "$temporary" ;;
    *) exit 1 ;;
esac
cp "$root/scripts/test.sh" "$root/scripts/postgresql-versions.sh" "$temporary/$archive/"
if [[ "$TARGET" == *linux* ]]; then
    : "${PLATFORM:?Missing container platform}"
    : "${RUNTIME_IMAGE:?Missing runtime image}"
    # Positional arguments also work with macOS's Bash 3.2 and nounset.
    set -- docker run --rm --platform "$PLATFORM" --user nobody
    if [ -n "${QEMU_CPU:-}" ]; then set -- "$@" --env "QEMU_CPU=$QEMU_CPU"; fi
    "$@" \
        --volume "$temporary/$archive:/opt/test:ro" \
        --tmpfs /usr/share/zoneinfo:ro --tmpfs /tmp:mode=1777 "$RUNTIME_IMAGE" \
        /bin/sh -c 'cd /opt/test && sh ./test.sh "$1"' sh "$version"
elif [[ "$TARGET" == *apple* ]]; then
    (cd "$temporary/$archive" && sandbox-exec -p '(version 1)(allow default)(deny file-read* (subpath "/opt/homebrew") (subpath "/usr/local") (subpath "/usr/share/zoneinfo"))' /bin/bash ./test.sh "$version")
else
    (cd "$temporary/$archive" && ./test.sh "$version")
fi
"$root/scripts/verify-checksum.sh" "$asset" "$asset.sha256"
