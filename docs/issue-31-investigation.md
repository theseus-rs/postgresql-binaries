# Release 18.6.0 investigation (2026-09-27)

A fresh unauthenticated public download of
`postgresql-18.6.0-x86_64-unknown-linux-gnu.tar.gz` from the
[18.6.0 release](https://github.com/theseus-rs/postgresql-binaries/releases/tag/18.6.0)
had SHA-256
`bb3d09f876b2383e25a8c9ce09e32d185a03656a23d074f5195542b1b1b3ca61`.
This matched both its public checksum file and GitHub's release-asset digest.

The extracted `bin/postgres --version` returned `postgres (PostgreSQL) 18.6`.
An initialized server returned `180006` for `SHOW server_version_num`.
Execution used an existing x86_64 Debian Bookworm Rust image with the necessary
runtime libraries and an isolated temporary database. This is version evidence,
not evidence that the old archive is self-contained on a clean host.

The reported 18.1 result in [#31](https://github.com/theseus-rs/postgresql-binaries/issues/31)
was not reproduced for that asset. No replacement asset or packaging revision
is proposed on this evidence. Other target assets still require independent
execution. A downstream reproduction should record the actual executable path,
archive digest, download URL, and running server's data directory and port.

The updated pipeline records the tested archive digest, compares uploaded draft
bytes with it, validates the complete draft inventory before publication, and
downloads and runs public archives in separate jobs afterward. Failures remain
visible as failed release workflow jobs; public verification failure must be
investigated rather than silently replacing existing assets.
