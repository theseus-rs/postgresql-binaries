# Release provenance

Each installation includes `source-input.json`, `build-manifest.json`, and
`target-validation.json`. Source builds also include `runtime-dependencies.json`
and `dependency-notices/`. These record the resolved PostgreSQL source commit,
source/input digests, checked-out build revision, target, compiler/configure
settings, generated features, and bundled/system dependency inventory. Windows
source builds retain PostgreSQL, vcpkg, and CPython notices. Buildroot targets
also record their build configuration and dependency builder.
Source-server authentication uses CA-validated HTTPS; no release-tag signature
is claimed.

Each archive has a standard `<sha256>  <filename>` checksum, a `.manifest.json`
inventory with per-file hashes/symlink targets, and a `.spdx.json` SBOM. The
manifest's archive digest is external to avoid a self-referential hash. SBOM
license fields use `NOASSERTION` when package metadata cannot establish a license;
this is not a substitute for preserving the actual notices. Alpine source
notices are collected from the installed package's immutable aports recipe and
SHA-512-verified source archives. Missing notices block release publication.

Release jobs create GitHub artifact provenance and SBOM attestations using OIDC.
Only the release caller grants `id-token: write` and `attestations: write`; PR
builds generate inspectable manifests and SBOMs without publishing attestations.
The draft and public gates validate archive inventories and artifact signatures.

```sh
./scripts/verify-checksum.sh "$asset" "$asset.sha256"
python3 scripts/archive-manifest.py verify "$asset"
gh attestation verify "$asset" --repo theseus-rs/postgresql-binaries
```

Attestations establish the repository/workflow identity and subject digest; they
do not prove a reproducible build or absence of vulnerabilities. Apt, apk and
Homebrew package inputs remain repository-resolved rather than a fully frozen
dependency snapshot. Review the recorded package versions and notice sources.
