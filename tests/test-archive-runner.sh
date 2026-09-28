#!/usr/bin/env bash

set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
archive=postgresql-18.6.0-aarch64-unknown-linux-gnu
mkdir -p "$temporary/$archive/bin" "$temporary/tools"
cat > "$temporary/tools/docker" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$DOCKER_TEST_LOG"
exit "${DOCKER_TEST_STATUS:-0}"
SH
chmod +x "$temporary/tools/docker"
COPYFILE_DISABLE=1 tar czf "$temporary/$archive.tar.gz" -C "$temporary" "$archive"
python3 "$root/scripts/checksum.py" "$temporary/$archive.tar.gz" > "$temporary/$archive.tar.gz.sha256"
export PATH="$temporary/tools:$PATH" DOCKER_TEST_LOG="$temporary/docker.log"
export TARGET=aarch64-unknown-linux-gnu PLATFORM=linux/arm64 RUNTIME_IMAGE=test-only
unset QEMU_CPU
bash "$root/scripts/test-archive.sh" "$temporary/$archive.tar.gz" 18.6.0
test -s "$DOCKER_TEST_LOG"
export QEMU_CPU=arm1176
bash "$root/scripts/test-archive.sh" "$temporary/$archive.tar.gz" 18.6.0
grep -q -- '--env QEMU_CPU=arm1176' "$DOCKER_TEST_LOG"
export DOCKER_TEST_STATUS=7
if bash "$root/scripts/test-archive.sh" "$temporary/$archive.tar.gz" 18.6.0; then
    echo 'Archive verification ignored a failed runtime command' >&2
    exit 1
fi
echo 'Archive runner invocation and failure propagation passed'
