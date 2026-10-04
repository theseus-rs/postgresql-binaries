#!/usr/bin/env bash

set -euo pipefail
version="${1:?Usage: verify-release.sh <version> <draft|public>}"
mode="${2:?Missing download mode}"
[[ "$version" =~ ^(14|15|16|17|18)\.[0-9]+\.[0-9]+$ ]]
[[ "$mode" == draft || "$mode" == public ]]
root=$(cd "$(dirname "$0")/.." && pwd)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
repository=${GITHUB_REPOSITORY:-theseus-rs/postgresql-binaries}

# Derive the expected inventory from the build matrix, not the release listing:
# an incomplete release must not pass by only checking what happens to exist.
targets=$(sed -n 's/^            target: //p' "$root/.github/workflows/build.yml")
test -n "$targets"
for target in $targets; do
    extensions=(tar.gz)
    if [[ "$target" == *windows* ]]; then extensions+=(zip); fi
    for extension in "${extensions[@]}"; do
        asset="postgresql-$version-$target.$extension"
        if [ "$mode" = draft ]; then
            gh release download "$version" --repo "$repository" --dir "$temporary" \
                --pattern "$asset" --pattern "$asset.sha256"
        else
            for file in "$asset" "$asset.sha256"; do
                curl --fail --location --silent --show-error --retry 3 \
                    --proto '=https' --proto-redir '=https' \
                    "https://github.com/$repository/releases/download/$version/$file" \
                    -o "$temporary/$file"
            done
        fi
        "$root/scripts/verify-checksum.sh" "$temporary/$asset" "$temporary/$asset.sha256"
        if [ "$extension" = tar.gz ]; then tar tzf "$temporary/$asset" >/dev/null; fi
    done
done
