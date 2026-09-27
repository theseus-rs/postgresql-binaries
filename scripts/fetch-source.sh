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

# TLS authenticates the upstream server. Do not inherit a local TLS bypass.
# A failed clone is fatal; never build a partial checkout left by a retry.
git -c http.sslVerify=true -c http.version=HTTP/1.1 clone \
    --depth 1 --branch "$tag" -c advice.detachedHead=false "$url" "$destination"
commit=$(git -C "$destination" rev-parse --verify HEAD)
[[ "$commit" =~ ^[0-9a-f]{40}$ ]]
test "$commit" = "$(git -C "$destination" rev-parse --verify "refs/tags/$tag^{commit}")"
git -C "$destination" archive --format=tar HEAD > "$destination/source.tar"
digest=$(shasum -a 256 "$destination/source.tar" | awk '{print $1}')
rm "$destination/source.tar"
[[ "$digest" =~ ^[0-9a-f]{64}$ ]]
if ! grep -Fq "AC_INIT([PostgreSQL], [$upstream_version]" "$destination/configure.ac"; then
    echo 'Source version does not match the requested release' >&2
    exit 1
fi

# The URL is constant; all other interpolated fields are validated above and
# contain only release-tag characters or hexadecimal digits, so need no escaping.
cat > "$destination/source-input.json" <<JSON
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
