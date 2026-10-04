#!/usr/bin/env bash

set -euo pipefail

version="${1:?Usage: fetch-source.sh <major.minor.revision> <destination>}"
destination="${2:?Missing destination}"
if [[ ! "$version" =~ ^(14|15|16|17|18)\.[0-9]+\.[0-9]+$ ]]; then
    echo "Unsupported or malformed PostgreSQL version: $version" >&2
    exit 1
fi
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
downloaded=false
for url in "$url" https://github.com/postgres/postgres.git; do
    for attempt in 1 2 3; do
        if git -c http.sslVerify=true -c http.version=HTTP/1.1 clone \
            --depth 1 --branch "$tag" -c advice.detachedHead=false "$url" "$checkout"; then
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
digest=$(shasum -a 256 "$temporary/source.tar" | awk '{print $1}')
if [[ ! "$digest" =~ ^[0-9a-f]{64}$ ]]; then
    echo 'Invalid source archive digest' >&2
    exit 1
fi
if ! grep -Fq "AC_INIT([PostgreSQL], [$upstream_version]" "$checkout/configure.ac"; then
    echo 'Source version does not match the requested release' >&2
    exit 1
fi

# The URLs are constant; all other interpolated fields are validated above and
# contain only release-tag characters or hexadecimal digits, so need no escaping.
cat > "$checkout/source-input.json" <<JSON
{
  "url": "$url",
  "tag": "$tag",
  "commit": "$commit",
  "version": "$upstream_version",
  "git_archive_sha256": "$digest",
  "authentication": "upstream HTTPS with CA validation",
  "signature_verified": false
}
JSON
mv "$checkout" "$destination"
