#!/usr/bin/env bash

set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT

expect_failure() {
    if "$@" > "$temporary/failure.log" 2>&1; then
        echo "Unexpected success: $*" >&2
        cat "$temporary/failure.log" >&2
        exit 1
    fi
}

mkdir "$temporary/assets with spaces"
asset="$temporary/assets with spaces/archive.tar.gz"
checksum="$asset.sha256"
empty_digest=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
empty_record="$empty_digest  archive.tar.gz"
printf '' > "$asset"
printf '%s\n' "$empty_record" > "$checksum"
"$root/scripts/checksum.sh" "$asset" > "$temporary/actual"
cmp "$checksum" "$temporary/actual"
"$root/scripts/verify-checksum.sh" "$asset" "$checksum" > "$temporary/actual"
cmp "$checksum" "$temporary/actual"

# Accept both platform line endings and a record without a final newline.
printf '%s\r\n' "$empty_record" > "$checksum"
"$root/scripts/verify-checksum.sh" "$asset" "$checksum" > /dev/null
printf '%s' "$empty_record" > "$checksum"
"$root/scripts/verify-checksum.sh" "$asset" "$checksum" > /dev/null

printf 'tampered' > "$asset"
expect_failure "$root/scripts/verify-checksum.sh" "$asset" "$checksum"
printf '' > "$asset"

# Use the correct digest so these failures specifically exercise record parsing.
for record in "$empty_digest  other.tar.gz" "$empty_digest archive.tar.gz" invalid ''; do
    printf '%s\n' "$record" > "$checksum"
    expect_failure "$root/scripts/verify-checksum.sh" "$asset" "$checksum"
done
for extra in "$empty_record" extra ''; do
    printf '%s\n%s\n' "$empty_record" "$extra" > "$checksum"
    expect_failure "$root/scripts/verify-checksum.sh" "$asset" "$checksum"
done
printf '%s\nextra' "$empty_record" > "$checksum"
expect_failure "$root/scripts/verify-checksum.sh" "$asset" "$checksum"
printf '%s\0\n' "$empty_record" > "$checksum"
expect_failure "$root/scripts/verify-checksum.sh" "$asset" "$checksum"

# Check nonempty bytes, multiple arguments, and spaces in the asset basename.
second_asset="$temporary/assets with spaces/second archive.zip"
printf 'abc' > "$second_asset"
second_record='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  second archive.zip'
printf '%s\n' "$empty_record" "$second_record" > "$temporary/expected"
"$root/scripts/checksum.sh" "$asset" "$second_asset" > "$temporary/actual"
cmp "$temporary/expected" "$temporary/actual"
printf '%s\n' "$second_record" > "$second_asset.sha256"
"$root/scripts/verify-checksum.sh" "$second_asset" "$second_asset.sha256" > /dev/null
expect_failure "$root/scripts/checksum.sh" "$temporary/missing"
expect_failure "$root/scripts/verify-checksum.sh" "$asset" "$temporary/missing.sha256"

# Exercise the macOS fallback with sha256sum absent from PATH.
mkdir "$temporary/fallback-bin"
for tool in bash dirname wc shasum; do
    ln -s "$(command -v "$tool")" "$temporary/fallback-bin/$tool"
done
PATH="$temporary/fallback-bin" "$root/scripts/checksum.sh" "$asset" "$second_asset" > "$temporary/actual"
cmp "$temporary/expected" "$temporary/actual"
PATH="$temporary/fallback-bin" "$root/scripts/verify-checksum.sh" "$second_asset" "$second_asset.sha256" > /dev/null

echo 'Checksum generation and rejection checks passed'
