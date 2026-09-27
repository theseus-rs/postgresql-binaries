#!/usr/bin/env bash

set -euo pipefail

version="${1:?Usage: fetch-windows.sh <major.minor.revision> <archive>}"
archive="${2:?Missing output archive}"
[[ "$version" =~ ^(14|15|16|17|18)\.[0-9]+\.[0-9]+$ ]]
upstream_version="${version%.*}"
url="https://get.enterprisedb.com/postgresql/postgresql-$upstream_version-1-windows-x64-binaries.zip"
curl --fail --location --show-error --silent --retry 3 \
    --proto '=https' --proto-redir '=https' --tlsv1.2 "$url" -o "$archive"
# EDB does not publish a SHA-256 sidecar at this URL (403 as of 2026-09-27).
# Record the authenticated transport and digest; do not invent a signature claim.
python3 - "$archive" "$url" "$upstream_version" <<'PY'
import hashlib
import json
import pathlib
import sys
import zipfile

archive, url, version = sys.argv[1:]
with zipfile.ZipFile(archive) as z:
    if z.testzip() is not None or "pgsql/bin/postgres.exe" not in z.namelist():
        raise SystemExit("Invalid EDB binary archive")
digest = hashlib.file_digest(open(archive, "rb"), "sha256").hexdigest()
pathlib.Path("windows-input.json").write_text(json.dumps({
    "url": url, "version": version, "sha256": digest,
    "authentication": "EDB HTTPS with CA validation",
    "signature_verified": False,
    "verification_limit": "No independently published upstream SHA-256 or archive signature",
}, indent=2) + "\n")
PY
