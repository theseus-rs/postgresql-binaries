#!/usr/bin/env bash

set -euo pipefail

version="${1:?Usage: fetch-windows.sh <major.minor.revision> <archive>}"
archive="${2:?Missing output archive}"
if [[ ! "$version" =~ ^(14|15|16|17|18)\.[0-9]+\.[0-9]+$ ]]; then
    echo "Unsupported or malformed PostgreSQL version: $version" >&2
    exit 1
fi
upstream_version="${version%.*}"
url="https://get.enterprisedb.com/postgresql/postgresql-$upstream_version-1-windows-x64-binaries.zip"
curl --fail --location --show-error --silent --retry 3 \
    --proto '=https' --proto-redir '=https' --tlsv1.2 "$url" -o "$archive"
# Validate every member's CRC and require the expected server executable. Read
# the complete listing so pipefail also catches errors from unzip.
unzip -tqq "$archive"
unzip -Z1 "$archive" | grep -Fx 'pgsql/bin/postgres.exe' > /dev/null
if command -v sha256sum > /dev/null 2>&1; then
    digest=$(sha256sum < "$archive" | awk '{print $1}')
else
    digest=$(shasum -a 256 < "$archive" | awk '{print $1}')
fi
if [[ ! "$digest" =~ ^[0-9a-f]{64}$ ]]; then
    echo 'Invalid Windows archive digest' >&2
    exit 1
fi
# EDB does not publish a SHA-256 sidecar at this URL (403 as of 2026-09-27).
# Record the authenticated transport and digest; do not invent a signature claim.
# The URL contains only a constant prefix/suffix and a validated version; the
# digest is hexadecimal, so these JSON fields need no additional escaping.
cat > windows-input.json <<JSON
{
  "url": "$url",
  "version": "$upstream_version",
  "sha256": "$digest",
  "authentication": "EDB HTTPS with CA validation",
  "signature_verified": false,
  "verification_limit": "No independently published upstream SHA-256 or archive signature"
}
JSON
