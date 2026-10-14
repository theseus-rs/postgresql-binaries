#!/usr/bin/env bash

set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT

# Use a real local Git repository, isolated from the user's Git configuration.
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$temporary/gitconfig"
touch "$GIT_CONFIG_GLOBAL"
git init --quiet --object-format=sha1 "$temporary/upstream"
printf 'AC_INIT([PostgreSQL], [18.6], [])\n' > "$temporary/upstream/configure.ac"
printf 'PG_LWLOCK(13, MultiXactGen)\n' > "$temporary/upstream/lwlocklist.h"
git -C "$temporary/upstream" add .
git -C "$temporary/upstream" -c user.name=Test -c user.email=test@example.invalid \
    commit --quiet -m fixture
git -C "$temporary/upstream" tag REL_18_6

# Reproduce runner checkout conversion without a network request. Ordinary
# Git clones must get CRLF, while fetch-source must preserve upstream LF bytes.
git config --global core.autocrlf true
git config --global core.eol crlf
git config --global "url.file://$temporary/upstream.insteadOf" \
    https://git.postgresql.org/git/postgresql.git
git clone --quiet "file://$temporary/upstream" "$temporary/crlf"
printf 'PG_LWLOCK(13, MultiXactGen)\r\n' > "$temporary/expected-crlf"
cmp "$temporary/expected-crlf" "$temporary/crlf/lwlocklist.h"

"$root/scripts/fetch-source.sh" 18.6.0 "$temporary/source with spaces"
cmp "$temporary/upstream/lwlocklist.h" "$temporary/source with spaces/lwlocklist.h"
cmp "$temporary/upstream/configure.ac" "$temporary/source with spaces/configure.ac"

# Match the line parser that failed in generate-lwlocknames.pl on Windows.
perl -ne 'chomp; die "Invalid lock definition: $_" unless /^PG_LWLOCK\((\d+),\s+(\w+)\)$/;' \
    "$temporary/source with spaces/lwlocklist.h"

# Reconstruct only the patch's old context, padding untouched lines. This keeps
# a real Git/apply fixture without vendoring a complete PostgreSQL checkout.
python3 - "$root/scripts/patches/postgresql-16.0-llvm16.patch" "$temporary/upstream" <<'PYTHON'
from pathlib import Path
import re
import sys

files = {}
current = None
position = None
for line in Path(sys.argv[1]).read_text().splitlines(keepends=True):
    if line.startswith('diff --git '):
        current = None
        position = None
    elif line.startswith('--- a/'):
        current = line[6:].strip()
        files[current] = []
    elif line.startswith('@@ '):
        position = int(re.match(r'@@ -(\d+)', line)[1]) - 1
    elif current and position is not None and line.startswith((' ', '-')):
        contents = files[current]
        while len(contents) <= position:
            contents.append('/* Unchanged fixture line. */\n')
        contents[position] = line[1:]
        position += 1
for name, contents in files.items():
    path = Path(sys.argv[2]) / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(''.join(contents))
PYTHON
printf 'AC_INIT([PostgreSQL], [16.0], [])\n' > "$temporary/upstream/configure.ac"
git -C "$temporary/upstream" -c core.autocrlf=false add .
git -C "$temporary/upstream" -c user.name=Test -c user.email=test@example.invalid \
    commit --quiet -m llvm-fixture
git -C "$temporary/upstream" tag REL_16_0
"$root/scripts/fetch-source.sh" 16.0.7 "$temporary/patched source"
git -C "$temporary/patched source" apply --reverse --check \
    "$root/scripts/patches/postgresql-16.0-llvm16.patch"
python3 - "$temporary/patched source/source-input.json" "$root/scripts/patches/postgresql-16.0-llvm16.patch" <<'PYTHON'
import hashlib
import json
from pathlib import Path
import sys

record = json.loads(Path(sys.argv[1]).read_text())
assert record['version'] == '16.0'
assert record['source_patches'] == [{
    'patch': 'postgresql-16.0-llvm16.patch',
    'sha256': hashlib.sha256(Path(sys.argv[2]).read_bytes()).hexdigest(),
}]
PYTHON
echo 'Source checkout preserves LF and applies the LLVM backport with Windows Git settings'
