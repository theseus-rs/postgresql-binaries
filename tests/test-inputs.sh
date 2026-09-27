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
echo 'Source fetching must not invoke Python' >&2
exit 99
SH
chmod +x "$temporary/bin/python3"
cat > "$temporary/bin/git" <<'SH'
#!/bin/sh
case " $* " in
    *' clone '*)
        for destination do :; done
        mkdir -p "$destination"
        printf 'AC_INIT([PostgreSQL], [%s], [])\n' "$FIXTURE_VERSION" > "$destination/configure.ac"
        ;;
    *' rev-parse '*) printf '%s\n' 724edf9bde9d356724ad384a2e196edc3c9f80f7 ;;
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
echo 'Input rejection checks passed'
