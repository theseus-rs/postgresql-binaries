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

## Building locally

The build workflow calls the same per-OS Bash scripts that can be run locally. Pass the full project
version (`<postgres major>.<postgres minor>.<release>`) and target triple. Linux also requires a Docker
platform, and Windows requires a vcpkg triplet; matching values are listed in
[the build matrix](.github/workflows/build.yml).

Run these examples from the repository root:

```bash
# Linux GNU or musl (requires Docker with Buildx and privileged container support)
./scripts/build-linux.sh 18.6.0 x86_64-unknown-linux-gnu linux/amd64
./scripts/build-linux.sh 18.6.0 x86_64-unknown-linux-musl linux/amd64

# macOS (requires Xcode command line tools and Homebrew)
./scripts/build-macos.sh 18.6.0 aarch64-apple-darwin
# On an Intel Mac, use x86_64-apple-darwin instead.

# Windows (run in Git Bash with the Visual Studio developer environment inherited)
./scripts/build-windows.sh 18.6.0 x86_64-pc-windows-msvc x64-windows
./scripts/build-windows.sh 18.6.0 aarch64-pc-windows-msvc arm64-windows
```

macOS and Windows builds require a host matching the target architecture. On Windows, install Visual
Studio C++ build tools, Python, and Chocolatey first, then launch Git Bash from a developer command
prompt configured for the target architecture. PostgreSQL versions before 16 also require Strawberry
Perl at `C:\Strawberry`; ARM64 builds require PostgreSQL 16 or newer. The scripts install the remaining
Homebrew, Python, Chocolatey, or vcpkg dependencies as needed.

The scripts resolve the repository root from their own location and install into
`postgresql-<version>-<target>` there. Set `INSTALL_DIRECTORY` to an absolute path to choose another
destination. macOS clones into `postgresql-src`; remove that generated directory before starting a
fresh build. Windows uses `RUNNER_TEMP`, falling back to `TMPDIR` or `/tmp`, for source and build files;
use a fresh temporary directory when changing versions or targets.

On macOS and Windows, the installation includes runtime dependencies and can be tested with:

```bash
cd postgresql-18.6.0-aarch64-apple-darwin # Use your installation directory.
../scripts/test.sh 18.6.0
```

Linux installations can be tested in the build image:

```bash
docker run --rm --platform linux/amd64 \
  --volume "$PWD/postgresql-18.6.0-x86_64-unknown-linux-gnu:/opt/test" \
  --volume "$PWD/scripts/test.sh:/opt/test/test.sh:ro" \
  postgresql-build:latest /bin/sh -c 'cd /opt/test && ./test.sh 18.6.0'
```

Archive creation and release uploads are handled by the GitHub Actions workflow.

## License

PostgreSQL is covered under [The PostgreSQL License](https://opensource.org/licenses/postgresql).
