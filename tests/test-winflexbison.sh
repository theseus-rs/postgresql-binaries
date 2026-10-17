#!/usr/bin/env bash

set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
mkdir "$temporary/bin" "$temporary/scripts"
cp "$root/scripts/"{install-winflexbison,build-diagnostics,verify-checksum,checksum}.sh "$temporary/scripts/"
export FIXTURE="$temporary/fixture.zip"
export CURL_LOG="$temporary/curl.log"
export PYTHON_LOG="$temporary/python.log"
export FIXTURE_PYTHON
FIXTURE_PYTHON=$(command -v python3)
"$FIXTURE_PYTHON" - "$FIXTURE" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], 'w') as archive:
    archive.writestr('win_flex.exe', b'flex fixture')
    archive.writestr('win_bison.exe', b'bison fixture')
    archive.writestr('data/skeletons/yacc.c', b'skeleton fixture')
PY
# Use a fixture checksum only in an isolated copy of the installer. Verification
# and extraction are real; no upstream download is needed for these regressions.
digest=$("$root/scripts/checksum.sh" "$FIXTURE")
digest=${digest%% *}
"$FIXTURE_PYTHON" - "$temporary/scripts/install-winflexbison.sh" "$digest" <<'PY'
from pathlib import Path
import re, sys
path = Path(sys.argv[1])
path.write_text(re.sub(r'^sha256=[0-9a-f]{64}$', 'sha256=' + sys.argv[2], path.read_text(), flags=re.M))
PY
cat > "$temporary/bin/curl" <<'SH'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$@" > "$CURL_LOG"
while [ "$#" -gt 0 ]; do
    if [ "$1" = --output ]; then output=$2; break; fi
    shift
done
cp "$FIXTURE" "$output"
exit "${DOWNLOAD_STATUS:-0}"
SH
cat > "$temporary/bin/python" <<'SH'
#!/usr/bin/env bash
echo called >> "$PYTHON_LOG"
exec "$FIXTURE_PYTHON" "$@"
SH
chmod +x "$temporary/bin/"*
export PATH="$temporary/bin:$PATH"
helper="$temporary/scripts/install-winflexbison.sh"

bash "$helper" "$temporary/install with spaces"
test "$(cat "$temporary/install with spaces/win_flex.exe")" = 'flex fixture'
test -f "$temporary/install with spaces/data/skeletons/yacc.c"
grep -Fx -- '--retry' "$CURL_LOG" >/dev/null
grep -Fx -- '--retry-max-time' "$CURL_LOG" >/dev/null
grep -Fx -- '=https' "$CURL_LOG" >/dev/null
test -z "$(find "$temporary" -name '*.download.*' -print)"

# Existing installations are never overwritten, and failed transfers leave no
# published installation or partial extraction (even if curl wrote some bytes).
rm "$CURL_LOG" "$PYTHON_LOG"
if bash "$helper" "$temporary/install with spaces" > /dev/null 2>&1; then exit 1; fi
test ! -e "$CURL_LOG"
if DOWNLOAD_STATUS=22 bash "$helper" "$temporary/download-failed" > /dev/null 2>&1; then exit 1; else status=$?; fi
test "$status" = 22
test ! -e "$temporary/download-failed"
test ! -e "$PYTHON_LOG"
test -z "$(find "$temporary" -name '*.download.*' -print)"

# A modified archive must fail verification before Python ever extracts it.
printf corrupted >> "$FIXTURE"
if bash "$helper" "$temporary/corrupt" > "$temporary/failure.log" 2>&1; then exit 1; fi
grep -F 'Checksum or filename mismatch' "$temporary/failure.log" >/dev/null
test ! -e "$PYTHON_LOG"
test ! -e "$temporary/corrupt"
test -z "$(find "$temporary" -name '*.download.*' -print)"
echo 'WinFlexBison installs atomically and rejects failed or corrupted downloads'
