#!/usr/bin/env bash

set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
mkdir "$temporary/bin"
export CALL_LOG="$temporary/calls"
export ATTEMPTS="$temporary/attempts"
cat > "$temporary/bin/docker" <<'SH'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$CALL_LOG"
case "$1" in
    image) exit "${CACHE_STATUS:-1}" ;;
    pull)
        count=0
        if [ -f "$ATTEMPTS" ]; then count=$(cat "$ATTEMPTS"); fi
        count=$((count + 1))
        echo "$count" > "$ATTEMPTS"
        if [ "$count" -le "${FAIL_ATTEMPTS:-0}" ]; then exit 42; fi
        ;;
    run) exit "${RUN_STATUS:-0}" ;;
    *) exit 99 ;;
esac
SH
cat > "$temporary/bin/sleep" <<'SH'
#!/usr/bin/env bash
printf 'sleep %s\n' "$1" >> "$CALL_LOG"
SH
chmod +x "$temporary/bin/"*
export PATH="$temporary/bin:$PATH"

# A transient registry error retries the pull and installs exactly once.
FAIL_ATTEMPTS=2 bash "$root/scripts/setup-binfmt.sh"
test "$(cat "$ATTEMPTS")" = 3
test "$(grep -c '^run ' "$CALL_LOG")" = 1
grep -Fx 'sleep 5' "$CALL_LOG" >/dev/null
grep -Fx 'sleep 10' "$CALL_LOG" >/dev/null
grep -E '^run --pull=never --privileged --rm tonistiigi/binfmt@sha256:[0-9a-f]{64} --install all$' "$CALL_LOG" >/dev/null

# Exhaustion retains the download failure and never runs the image.
rm "$ATTEMPTS" "$CALL_LOG"
if FAIL_ATTEMPTS=10 bash "$root/scripts/setup-binfmt.sh"; then exit 1; else status=$?; fi
test "$status" = 42
test "$(cat "$ATTEMPTS")" = 3
if grep -E '^(run |sleep 15)' "$CALL_LOG"; then exit 1; fi

# The digest-pinned local image needs no registry access. Installation errors
# must fail immediately rather than being retried as download failures.
rm "$ATTEMPTS" "$CALL_LOG"
if CACHE_STATUS=0 RUN_STATUS=4 bash "$root/scripts/setup-binfmt.sh"; then exit 1; else status=$?; fi
test "$status" = 4
test ! -e "$ATTEMPTS"
test "$(grep -c '^run ' "$CALL_LOG")" = 1
if grep -E '^(pull |sleep )' "$CALL_LOG"; then exit 1; fi
echo 'Emulator download retries are bounded and installation failures stay visible'
