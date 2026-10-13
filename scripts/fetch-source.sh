#!/usr/bin/env bash

set -euo pipefail

version="${1:?Usage: fetch-source.sh <major.minor.revision> <destination>}"
destination="${2:?Missing destination}"
script_directory=$(cd "$(dirname "$0")" && pwd)
sh "$script_directory/postgresql-versions.sh" validate "$version"
upstream_version="${version%.*}"
tag="REL_${upstream_version//./_}"
url=https://git.postgresql.org/git/postgresql.git
test ! -e "$destination"
test ! -L "$destination"
mkdir -p "$(dirname "$destination")"
temporary=$(mktemp -d "${destination}.fetch.XXXXXX")
trap 'rm -rf "$temporary"' EXIT
checkout="$temporary/source"

# TLS authenticates the upstream server. Do not inherit a local TLS bypass.
# Retry interrupted transfers in a fresh checkout. PostgreSQL's GitHub mirror
# provides a fallback when the upstream Git server cannot serve complete packs.
# Keep source files in LF form: Git Bash's Perl generators cannot parse CRLF
# input produced by the Windows runner's core.autocrlf setting.
downloaded=false
for url in "$url" https://github.com/postgres/postgres.git; do
    for attempt in 1 2 3; do
        if git -c http.sslVerify=true -c http.version=HTTP/1.1 clone \
            --depth 1 --branch "$tag" -c advice.detachedHead=false \
            -c core.autocrlf=false -c core.eol=lf "$url" "$checkout"; then
            downloaded=true
            break 2
        fi
        rm -rf "$checkout"
        echo "Source download failed ($url, attempt $attempt/3)" >&2
        if [ "$attempt" -lt 3 ]; then sleep "$attempt"; fi
    done
done
if [ "$downloaded" != true ]; then
    echo 'Unable to download a complete PostgreSQL source checkout' >&2
    exit 1
fi
commit=$(git -C "$checkout" rev-parse --verify HEAD)
if [[ ! "$commit" =~ ^[0-9a-f]{40}$ ]]; then
    echo 'Invalid source commit' >&2
    exit 1
fi
test "$commit" = "$(git -C "$checkout" rev-parse --verify "refs/tags/$tag^{commit}")"
git -C "$checkout" archive --format=tar HEAD > "$temporary/source.tar"
if command -v sha256sum > /dev/null 2>&1; then
    digest=$(sha256sum -b < "$temporary/source.tar")
else
    digest=$(shasum -a 256 -b < "$temporary/source.tar")
fi
digest="${digest%% *}"
if [[ ! "$digest" =~ ^[0-9a-f]{64}$ ]]; then
    echo 'Invalid source archive digest' >&2
    exit 1
fi
if ! grep -Fq "AC_INIT([PostgreSQL], [$upstream_version]" "$checkout/configure.ac"; then
    echo 'Source version does not match the requested release' >&2
    exit 1
fi

# Apply version-specific upstream compatibility fixes consistently on every OS.
# Record their hashes separately from the unmodified upstream Git archive.
source_patches=''
for source_patch in $(sh "$script_directory/postgresql-versions.sh" source-patches "$version"); do
    patch_file="$script_directory/patches/$source_patch"
    git -C "$checkout" apply --check "$patch_file"
    git -C "$checkout" apply "$patch_file"
    if command -v sha256sum > /dev/null 2>&1; then
        patch_digest=$(sha256sum -b < "$patch_file")
    else
        patch_digest=$(shasum -a 256 -b < "$patch_file")
    fi
    patch_digest="${patch_digest%% *}"
    [[ "$patch_digest" =~ ^[0-9a-f]{64}$ ]]
    source_patches="${source_patches:+$source_patches, }{\"patch\": \"$source_patch\", \"sha256\": \"$patch_digest\"}"
done

# URLs and patch names come from repository policy; versions and hashes above
# are validated release-tag characters or hexadecimal digits.
cat > "$checkout/source-input.json" <<JSON
{
  "url": "$url",
  "tag": "$tag",
  "commit": "$commit",
  "version": "$upstream_version",
  "git_archive_sha256": "$digest",
  "source_patches": [$source_patches],
  "authentication": "upstream HTTPS with CA validation",
  "signature_verified": false
}
JSON
mv "$checkout" "$destination"
