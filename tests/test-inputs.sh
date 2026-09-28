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

# Exercise successful metadata generation without a Python runtime, and reject
# a tag whose configure version disagrees with the requested release.
cat > "$temporary/bin/python3" <<'SH'
#!/bin/sh
echo 'Input fetching must not invoke Python' >&2
exit 99
SH
chmod +x "$temporary/bin/python3"
cp "$temporary/bin/python3" "$temporary/bin/python"
cat > "$temporary/bin/git" <<'SH'
#!/bin/sh
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
export FIXTURE_VERSION=18.6
"$root/scripts/fetch-source.sh" 18.6.0 "$temporary/source with spaces"
grep -Fq '"version": "18.6"' "$temporary/source with spaces/source-input.json"
grep -Fq '"commit": "724edf9bde9d356724ad384a2e196edc3c9f80f7"' "$temporary/source with spaces/source-input.json"
export FIXTURE_VERSION=18.5
if "$root/scripts/fetch-source.sh" 18.6.0 "$temporary/wrong-version"; then
    echo 'Mismatching source version accepted' >&2
    exit 1
fi
test ! -e "$temporary/wrong-version/source-input.json"
export FIXTURE_VERSION=18.6
export FIXTURE_COMMIT=invalid
if "$root/scripts/fetch-source.sh" 18.6.0 "$temporary/wrong-commit"; then
    echo 'Malformed source commit accepted' >&2
    exit 1
fi
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
if "$root/scripts/fetch-windows.sh" 18.6 'input archive.zip'; then
    echo 'Malformed Windows version accepted' >&2
    exit 1
fi
test ! -e "$CALL_LOG"
if FAIL_DOWNLOAD=1 "$root/scripts/fetch-windows.sh" 18.6.0 'input archive.zip'; then
    echo 'Failed Windows download accepted' >&2
    exit 1
fi
test ! -e windows-input.json
"$root/scripts/fetch-windows.sh" 18.6.0 'input archive.zip'
digest=$(shasum -a 256 < "$temporary/valid.zip" | awk '{print $1}')
grep -Fx "  \"sha256\": \"$digest\"," windows-input.json
grep -Fx '  "version": "18.6",' windows-input.json
grep -Fx '  "signature_verified": false,' windows-input.json
cp windows-input.json expected-input.json
# Exercise the macOS shasum fallback with sha256sum absent from PATH.
mkdir "$temporary/fallback-bin"
for tool in bash cat cp curl unzip grep awk shasum python python3; do
    ln -s "$(command -v "$tool")" "$temporary/fallback-bin/$tool"
done
PATH="$temporary/fallback-bin" "$root/scripts/fetch-windows.sh" 18.6.0 'input archive.zip'
cmp windows-input.json expected-input.json
rm windows-input.json
for invalid in wrong-layout malformed corrupt; do
    export FIXTURE_ARCHIVE="$temporary/$invalid.zip"
    if "$root/scripts/fetch-windows.sh" 18.6.0 'input archive.zip'; then
        echo "Invalid Windows archive accepted: $invalid" >&2
        exit 1
    fi
    test ! -e windows-input.json
done
export FIXTURE_ARCHIVE="$temporary/valid.zip"
cat > "$temporary/bin/sha256sum" <<'SH'
#!/bin/sh
printf 'invalid digest\n'
exit "${FAIL_CHECKSUM:-0}"
SH
chmod +x "$temporary/bin/sha256sum"
for status in 0 42; do
    if FAIL_CHECKSUM="$status" "$root/scripts/fetch-windows.sh" 18.6.0 'input archive.zip'; then
        echo 'Invalid or failed checksum accepted' >&2
        exit 1
    fi
    test ! -e windows-input.json
done
echo 'Input rejection checks passed'
