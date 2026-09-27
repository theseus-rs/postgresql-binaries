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
test "$commit" = "$(git -C "$destination" rev-parse --verify "refs/tags/$tag^{commit}")"
git -C "$destination" archive --format=tar HEAD > "$destination/source.tar"
digest=$(shasum -a 256 "$destination/source.tar" | awk '{print $1}')
rm "$destination/source.tar"
python3 - "$destination" "$url" "$tag" "$commit" "$digest" "$upstream_version" <<'PY'
import json
import pathlib
import sys

directory, url, tag, commit, digest, version = sys.argv[1:]
source = pathlib.Path(directory)
if f"AC_INIT([PostgreSQL], [{version}]" not in (source / "configure.ac").read_text():
    raise SystemExit("Source version does not match the requested release")
(source / "source-input.json").write_text(json.dumps({
    "url": url, "tag": tag, "commit": commit, "version": version,
    "git_archive_sha256": digest, "authentication": "upstream HTTPS with CA validation",
    "signature_verified": False,
}, indent=2) + "\n")
PY
