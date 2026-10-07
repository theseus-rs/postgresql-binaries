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
case " $* " in
    *' clone '*)
        case " $* " in
            *' -c http.sslVerify=true -c http.version=HTTP/1.1 clone '*) ;;
            *) exit 42 ;;
        esac
        for destination do :; done
        test ! -e "$destination" || exit 42
        mkdir -p "$destination"
        if [ "${FAIL_DOWNLOAD:-0}" = 1 ]; then
            touch "$destination/partial"
            exit 42
        fi
        if [ "${FAIL_UPSTREAM:-0}" = 1 ]; then
            case " $* " in
                *' https://git.postgresql.org/git/postgresql.git '*)
                    touch "$destination/partial"
                    exit 42
                    ;;
            esac
        fi
        if [ -n "${FAIL_ONCE_FILE:-}" ] && [ ! -e "$FAIL_ONCE_FILE" ]; then
            touch "$FAIL_ONCE_FILE" "$destination/partial"
            exit 42
        fi
        printf 'AC_INIT([PostgreSQL], [%s], [])\n' "$FIXTURE_VERSION" > "$destination/configure.ac"
        ;;
    *' rev-parse '*)
        case " $* " in
            *' refs/tags/'*) printf '%s\n' "${FIXTURE_TAG_COMMIT:-${FIXTURE_COMMIT:-724edf9bde9d356724ad384a2e196edc3c9f80f7}}" ;;
            *) printf '%s\n' "${FIXTURE_COMMIT:-724edf9bde9d356724ad384a2e196edc3c9f80f7}" ;;
        esac
        ;;
    *' archive '*) printf '%s\n' 'test source archive' ;;
    *) exit 42 ;;
esac
SH
printf '#!/bin/sh\nexit 0\n' > "$temporary/bin/sleep"
chmod +x "$temporary/bin/git" "$temporary/bin/sleep"
export CALL_LOG="$temporary/calls"
export FIXTURE_VERSION="$upstream_version"
export PATH="$temporary/bin:$PATH"

# Reject invalid versions before fetching, and stop when a download fails.
expect_failure "$root/scripts/fetch-source.sh" "$upstream_version" "$temporary/invalid"
test ! -e "$CALL_LOG"
expect_failure env FAIL_DOWNLOAD=1 "$root/scripts/fetch-source.sh" "$version" "$temporary/source"
test "$(wc -l < "$CALL_LOG" | tr -d ' ')" = 6
test ! -e "$temporary/source"
test -z "$(find "$temporary" -name 'source.fetch.*' -print)"

# A retry and a mirror fallback must discard files left by failed clones.
env FAIL_ONCE_FILE="$temporary/failed-once" "$root/scripts/fetch-source.sh" "$version" "$temporary/retried"
test ! -e "$temporary/retried/partial"
grep -Fq 'https://git.postgresql.org/git/postgresql.git' "$temporary/retried/source-input.json"
env FAIL_UPSTREAM=1 "$root/scripts/fetch-source.sh" "$version" "$temporary/mirrored"
test ! -e "$temporary/mirrored/partial"
grep -Fq 'https://github.com/postgres/postgres.git' "$temporary/mirrored/source-input.json"
expect_failure "$root/scripts/fetch-source.sh" "$version" "$temporary/mirrored"
test -f "$temporary/mirrored/source-input.json"
"$root/scripts/fetch-source.sh" "$version" "$temporary/new/parent/source"
test -f "$temporary/new/parent/source/source-input.json"

# Check metadata and reject mismatched source versions or malformed commits.
"$root/scripts/fetch-source.sh" "$version" "$temporary/source with spaces"
grep -Fq "\"version\": \"$upstream_version\"" "$temporary/source with spaces/source-input.json"
grep -Fq '"commit": "724edf9bde9d356724ad384a2e196edc3c9f80f7"' "$temporary/source with spaces/source-input.json"
expect_failure env FIXTURE_VERSION=0.0 "$root/scripts/fetch-source.sh" "$version" "$temporary/wrong-version"
test ! -e "$temporary/wrong-version/source-input.json"
expect_failure env FIXTURE_COMMIT=invalid "$root/scripts/fetch-source.sh" "$version" "$temporary/wrong-commit"
test ! -e "$temporary/wrong-commit/source-input.json"
expect_failure env FIXTURE_TAG_COMMIT=0000000000000000000000000000000000000000 "$root/scripts/fetch-source.sh" "$version" "$temporary/wrong-tag"
test ! -e "$temporary/wrong-tag"

# Git Bash provides sha256sum but not shasum. Source metadata must still
# contain the correct digest without depending on a Perl installation.
mkdir "$temporary/source-bin"
for tool in bash cat dirname git grep mkdir mktemp mv rm sha256sum; do
    ln -s "$(command -v "$tool")" "$temporary/source-bin/$tool"
done
PATH="$temporary/source-bin" "$root/scripts/fetch-source.sh" "$version" "$temporary/sha256sum source"
digest=$(printf '%s\n' 'test source archive' | shasum -a 256)
digest="${digest%% *}"
grep -Fxq "  \"git_archive_sha256\": \"$digest\"," "$temporary/sha256sum source/source-input.json"

echo 'Input rejection checks passed'
