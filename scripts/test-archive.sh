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
case "$asset" in
    *.tar.gz) tar xzf "$asset" -C "$temporary" ;;
    *.zip) unzip -q "$asset" -d "$temporary" ;;
    *) exit 1 ;;
esac
cp "$root/scripts/test.sh" "$temporary/$archive/test.sh"
if [[ "$TARGET" == *linux* ]]; then
    : "${PLATFORM:?Missing container platform}"
    : "${RUNTIME_IMAGE:?Missing runtime image}"
    docker run --rm --platform "$PLATFORM" --user nobody \
        --volume "$temporary/$archive:/opt/test:ro" \
        --tmpfs /tmp:mode=1777 "$RUNTIME_IMAGE" \
        /bin/bash -c 'cd /opt/test && ./test.sh "$1"' bash "$version"
else
    (cd "$temporary/$archive" && ./test.sh "$version")
fi
"$root/scripts/verify-checksum.sh" "$asset" "$asset.sha256"
