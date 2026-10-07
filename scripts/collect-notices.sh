#!/usr/bin/env bash

set -eo pipefail
script_directory=$(cd "$(dirname "$0")" && pwd)
source "$script_directory/runtime-common.sh"
root=${1:?Usage: collect-notices.sh <install_directory>}
notices="$root/dependency-notices"
mkdir -p "$notices"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
jq -c '.bundled[]' "$root/runtime-dependencies.json" > "$temporary/items"
: > "$temporary/bundled"
: > "$temporary/missing"
while IFS= read -r item; do
    source_file=$(printf '%s\n' "$item" | jq -er '.source')
    file=$(printf '%s\n' "$item" | jq -er '.file')
    paths=() package='' package_version=''
    if command -v dpkg-query >/dev/null && [ -f /var/lib/dpkg/status ]; then
        for spelling in "$source_file" "${source_file#/usr}"; do
            if result=$(dpkg-query -S "$spelling" 2>/dev/null); then
                package=${result%%: *}
                package_version=$(dpkg-query -W '-f=${Version}' "$package")
                paths=("/usr/share/doc/${package%%:*}/copyright")
                break
            fi
        done
    elif [ "$(uname -s)" = Darwin ]; then
        parent=${source_file%/*}
        while [ "$parent" != / ] && [ -n "$parent" ]; do
            formula=${parent%/*}
            cellar=${formula%/*}
            if [ "${cellar##*/}" = Cellar ]; then
                package=${formula##*/}
                package_version=${parent##*/}
                find "$parent" -type f \( -iname 'LICENSE*' -o -iname 'COPYING*' -o -iname 'NOTICE*' -o -iname 'COPYRIGHT*' \) -print0 > "$temporary/paths"
                while IFS= read -r -d '' path; do paths+=("$path"); done < "$temporary/paths"
                break
            fi
            parent=${parent%/*}
        done
    else
        result=$(apk info --who-owns "$source_file")
        package=${result##* owned by }
        if [ -d /usr/share/licenses ]; then
            find /usr/share/licenses -type f -print0 > "$temporary/paths"
            while IFS= read -r -d '' path; do paths+=("$path"); done < "$temporary/paths"
        fi
    fi
    if [ -n "$package" ]; then
        item=$(printf '%s\n' "$item" | jq -c --arg package "$package" '.package = $package')
    fi
    if [ -n "$package_version" ]; then
        item=$(printf '%s\n' "$item" | jq -c --arg version "$package_version" '.package_version = $version')
    fi
    index=0
    for path in "${paths[@]}"; do
        [ -f "$path" ] || continue
        folder=${package:-${source_file##*/}}
        folder="$notices/${folder//:/_}"
        mkdir -p "$folder"
        cp -p "$path" "$folder/$index-${path##*/}"
        index=$((index + 1))
    done
    if [ "$index" = 0 ]; then jq -cn --arg file "$file" '$file' >> "$temporary/missing"; fi
    printf '%s\n' "$item" >> "$temporary/bundled"
done < "$temporary/items"
jq --slurpfile bundled "$temporary/bundled" --slurpfile missing "$temporary/missing" \
    '.bundled = $bundled | .missing_notices = $missing' "$root/runtime-dependencies.json" > "$temporary/record"
cat "$temporary/record" > "$root/runtime-dependencies.json"
if [ -s "$temporary/missing" ]; then
    jq -r '"Missing dependency notices; release is blocked: " + (.missing_notices | join(", "))' "$root/runtime-dependencies.json" >&2
fi
