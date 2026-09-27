#!/usr/bin/env bash

set -euo pipefail
version="${1:-18.6.0}"
upstream_version="${version%.*}"
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

mkdir "$temporary/bin"
cat > "$temporary/bin/git" <<'SH'
#!/bin/sh
echo called >> "$CALL_LOG"
if [ "${FAIL_DOWNLOAD:-0}" = 1 ]; then exit 42; fi
case " $* " in
    *' clone '*)
        for destination do :; done
        mkdir -p "$destination"
        printf 'AC_INIT([PostgreSQL], [%s], [])\n' "$FIXTURE_VERSION" > "$destination/configure.ac"
        ;;
    *' rev-parse '*) printf '%s\n' "${FIXTURE_COMMIT:-724edf9bde9d356724ad384a2e196edc3c9f80f7}" ;;
    *' archive '*) printf '%s\n' 'test source archive' ;;
    *) exit 42 ;;
esac
SH
chmod +x "$temporary/bin/git"
export CALL_LOG="$temporary/calls"
export FIXTURE_VERSION="$upstream_version"
export PATH="$temporary/bin:$PATH"

# Reject invalid versions before fetching, and stop when a download fails.
expect_failure "$root/scripts/fetch-source.sh" "$upstream_version" "$temporary/invalid"
test ! -e "$CALL_LOG"
expect_failure env FAIL_DOWNLOAD=1 "$root/scripts/fetch-source.sh" "$version" "$temporary/source"
test "$(wc -l < "$CALL_LOG" | tr -d ' ')" = 1
test ! -e "$temporary/source/source-input.json"

# Check metadata and reject mismatched source versions or malformed commits.
"$root/scripts/fetch-source.sh" "$version" "$temporary/source with spaces"
grep -Fq "\"version\": \"$upstream_version\"" "$temporary/source with spaces/source-input.json"
grep -Fq '"commit": "724edf9bde9d356724ad384a2e196edc3c9f80f7"' "$temporary/source with spaces/source-input.json"
expect_failure env FIXTURE_VERSION=0.0 "$root/scripts/fetch-source.sh" "$version" "$temporary/wrong-version"
test ! -e "$temporary/wrong-version/source-input.json"
expect_failure env FIXTURE_COMMIT=invalid "$root/scripts/fetch-source.sh" "$version" "$temporary/wrong-commit"
test ! -e "$temporary/wrong-commit/source-input.json"

# Use real ZIP tools for Windows archive CRC/layout checks, with only the
# network download mocked. The output path deliberately contains spaces.
mkdir -p "$temporary/fixture/pgsql/bin" "$temporary/windows"
printf 'edb-fixture' > "$temporary/fixture/pgsql/bin/postgres.exe"
(cd "$temporary/fixture" && zip -q -0 -X "$temporary/valid.zip" pgsql/bin/postgres.exe)
printf 'wrong layout' > "$temporary/fixture/other.txt"
(cd "$temporary/fixture" && zip -q "$temporary/wrong-layout.zip" other.txt)
printf 'not a ZIP' > "$temporary/malformed.zip"
cp "$temporary/valid.zip" "$temporary/corrupt.zip"
# -X excludes extra fields; the stored member starts after its local header.
member=pgsql/bin/postgres.exe
printf '!' | dd of="$temporary/corrupt.zip" bs=1 seek=$((30 + ${#member})) conv=notrunc 2>/dev/null
cat > "$temporary/bin/curl" <<'SH'
#!/bin/sh
echo called >> "$CALL_LOG"
if [ "${FAIL_DOWNLOAD:-0}" = 1 ]; then exit 42; fi
while [ "$#" -gt 0 ]; do
    if [ "$1" = -o ]; then cp "$FIXTURE_ARCHIVE" "$2"; exit; fi
    shift
done
exit 1
SH
chmod +x "$temporary/bin/curl"
export CALL_LOG="$temporary/windows-calls"
export FIXTURE_ARCHIVE="$temporary/valid.zip"
cd "$temporary/windows"
expect_failure "$root/scripts/fetch-windows.sh" "$upstream_version" 'input archive.zip'
test ! -e "$CALL_LOG"
expect_failure env FAIL_DOWNLOAD=1 "$root/scripts/fetch-windows.sh" "$version" 'input archive.zip'
test ! -e windows-input.json
"$root/scripts/fetch-windows.sh" "$version" 'input archive.zip'
digest=$(shasum -a 256 < "$temporary/valid.zip" | awk '{print $1}')
grep -Fxq "  \"sha256\": \"$digest\"," windows-input.json
grep -Fxq "  \"version\": \"$upstream_version\"," windows-input.json
grep -Fxq '  "signature_verified": false,' windows-input.json
cp windows-input.json expected-input.json
# Exercise the macOS shasum fallback with sha256sum absent from PATH.
mkdir "$temporary/fallback-bin"
for tool in bash cat cp curl unzip grep awk shasum; do
    ln -s "$(command -v "$tool")" "$temporary/fallback-bin/$tool"
done
PATH="$temporary/fallback-bin" "$root/scripts/fetch-windows.sh" "$version" 'input archive.zip'
cmp windows-input.json expected-input.json
rm windows-input.json
for invalid in wrong-layout malformed corrupt; do
    expect_failure env FIXTURE_ARCHIVE="$temporary/$invalid.zip" "$root/scripts/fetch-windows.sh" "$version" 'input archive.zip'
    test ! -e windows-input.json
done
cat > "$temporary/bin/sha256sum" <<'SH'
#!/bin/sh
printf 'invalid digest\n'
exit "${FAIL_CHECKSUM:-0}"
SH
chmod +x "$temporary/bin/sha256sum"
for status in 0 42; do
    expect_failure env FAIL_CHECKSUM="$status" "$root/scripts/fetch-windows.sh" "$version" 'input archive.zip'
    test ! -e windows-input.json
done
echo 'Input rejection checks passed'
