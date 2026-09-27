# Input verification

Source builds fetch the exact PostgreSQL release tag from the upstream Git
server over HTTPS with certificate verification explicitly enabled. A failed
fetch, missing tag, or mismatching source version fails the build. Each archive
records the resolved commit and SHA-256 of its Git source archive in
`source-input.json`. This authenticates the server via the CA trust store; it
does not claim a verified release-tag signature or reproducible dependency set.

Windows x64 inputs come from EDB over certificate-validated HTTPS. The archive
CRC, expected layout, input SHA-256, and actual binary/server versions are
checked or recorded. EDB's [binary download page](https://www.enterprisedb.com/download-postgresql-binaries)
provides downloads but no independent SHA-256 or archive signature; the attempted
`.zip.sha256` endpoint returned HTTP 403 on 2026-09-27. Transport authentication
and a locally computed digest cannot provide independent publisher verification.
This limit is retained in the input record rather than silently claiming it.

External Actions and container indexes are pinned to immutable revisions.
Package repositories and Homebrew still supply changing dependencies; their
installed versions must be recorded in release provenance. Updating a base image
pin requires reviewing every advertised architecture and rerunning runtime tests.
