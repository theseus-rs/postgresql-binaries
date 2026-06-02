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
echo 'Source checkout preserves LF with Windows Git settings'
