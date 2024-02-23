# PostgreSQL Binaries

[![CI](https://github.com/theseus-rs/postgresql_binaries/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/theseus-rs/postgresql_binaries/actions?query=workflow%3Aci+branch%3Amain)
[![License](https://img.shields.io/github/license/theseus-rs/postgresql_binaries)](./LICENSE)
[![Github All Releases](https://img.shields.io/github/downloads/theseus-rs/postgresql-binaries/total.svg)]()

PostgreSQL binaries for Linux, MacOS and Windows; releases aligned with Rust [supported platforms](https://doc.rust-lang.org/nightly/rustc/platform-support.html).

---

## Choosing an installation package

Installation packages use the pattern `postgresql-<version>-<target>.<extension>`, where`<version>` is the
PostgreSQL version, `<target>` is the target triple for the platform, and `<extension>` is the archive file
extension.  To find the `<target>` triple for your platform run `rustc -vV` and look for the value of the
`host` field.  The target triple can be obtained programmatically in rust using the [target-triple](https://crates.io/crates/target-triple) crate.

## Versioning

This project uses a versioning scheme that is compatible with [PostgreSQL versioning](https://www.postgresql.org/support/versioning/).
The version comprises `<postgres major>.<postgres minor>.<release>`, where `<release>` is the release for
this project's build of a version of PostgreSQL.  New releases of this project will be made when new versions
of PostgreSQL are released or new builds of existing versions are required for bug fixes, new targets, etc.

## License

PostgreSQL is covered under [The PostgreSQL License](https://opensource.org/licenses/postgresql).
