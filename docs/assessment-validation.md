# September 27, 2026 validation record

This series starts from main commit
`2954f800589f74265f136cdb490b87749e209e7c`. It is a set of reviewable changes,
not a statement that all release acceptance checks have passed. No release
assets were replaced, releases published, PRs merged, or issues closed.

## Review order

The temporary stacked bases keep each review focused. Land in this order,
retargeting each successor to main as its predecessor lands. Preserve the
original contributor commit in #22; do not squash it away without agreement.

| PR | Work | Temporary base |
| --- | --- | --- |
| [#32](https://github.com/theseus-rs/postgresql-binaries/pull/32) | Source/input verification and immutable action/image pins | main |
| [#33](https://github.com/theseus-rs/postgresql-binaries/pull/33) | macOS version/feature selection | verify-source-downloads |
| [#34](https://github.com/theseus-rs/postgresql-binaries/pull/34) | Archive/draft/public verification and digest continuity | fix-macos-build-version |
| [#22](https://github.com/theseus-rs/postgresql-binaries/pull/22) | Bundled timezone data; contributor commit preserved | verify-release-assets |
| [#35](https://github.com/theseus-rs/postgresql-binaries/pull/35) | Recursive runtime bundling and relocation tests | remove-with-system-tzdata |
| [#36](https://github.com/theseus-rs/postgresql-binaries/pull/36) | GNU ICU and portable ICU dependency/data sets | fix-runtime-dependencies |
| [#37](https://github.com/theseus-rs/postgresql-binaries/pull/37) | Target/ABI validation and misleading alias quarantine | add-linux-gnu-icu-support |
| [#38](https://github.com/theseus-rs/postgresql-binaries/pull/38) | Manifests, SBOMs, notices and attestations | fix-target-validation |
| [#39](https://github.com/theseus-rs/postgresql-binaries/pull/39) | Support policy, upstream checks and integration matrix | add-release-provenance |

## Completed evidence

* A fresh public x64 GNU 18.6.0 download matched both its published checksum and
  GitHub asset digest. The executable reported 18.6 and the running server
  reported `180006`. See the digest and commands in
  [the #31 investigation](issue-31-investigation.md). This did not reproduce
  stale packaging and does not justify replacing or revising that asset.
* Native ARM64 macOS builds and runtime tests passed for 14.24, 15.19, 16.15,
  17.11 and 18.6. Execution denied Homebrew and system timezone directories.
  Tests exercised enabled ICU, compression, Python, JIT and extension branches.
  The host was Darwin 27; this does **not** establish the macOS 15 minimum.
  The target audit correctly rejected the local LLVM bottle's macOS 26 minimum.
* A source-built ARM64 musl 18.6 installation passed in a base Alpine 3.19
  container with system timezone and ICU data hidden. Tests exercised ICU
  case/accent behavior, UTC/New York, pgcrypto/xml2/hstore, LZ4, gzip/Zstandard
  dump/restore, Python SSL/JSON/zlib/decimal and forced LLVM JIT. The ELF audit
  passed and all 31 bundled library records had collected notices. This local
  root used the current 3.19 patch image, so the pinned 3.19.0 CI gate remains
  necessary.
* The native macOS 18.6 tar archive passed extraction/relocation, checksums,
  per-file manifest and SBOM verification. Safe timezone hardlinks are included
  in the inventory; escaping links and modified inventories are rejected.
* The compiled nested-module fixture passed on macOS and Linux after hiding
  the original dependency directory. Input rejection, macOS 14–18 option
  selection, checksum tampering, target ABI, PE imports/delay imports, manifest
  and upstream-feed regressions pass locally, as do Bash syntax and Actions
  workflow checks.
* EDB's actual PL/Python import tables select Python 3.9, 3.10, 3.11, 3.12 and
  3.13 for PostgreSQL 14–18 respectively. The Windows bundler detects this ABI
  and the checksum/manifest helpers support Python 3.9. These are input/header
  checks, not Windows runtime evidence for the new bundler.
* [PR #27's native Windows ARM64 18.6 job](https://github.com/theseus-rs/postgresql-binaries/actions/runs/36353376974/job/108716222694)
  passed with native MSVC/Python, PE machine `0xaa64`, extracted-server startup,
  version 18.6, UTF8 and plpgsql. Its contributor commit
  `05afa3eed999ba36561d34c83a088ef494b02a9d` is preserved. Its source-build path
  still needs the shared verification/bundling changes and native 16/17 tests.

## Remaining acceptance gates

The Integration workflow covers 19 enabled targets across five supported
majors. It and each PR's required CI must pass at the final submitted revisions;
queued, superseded or earlier smoke-test jobs are not final acceptance evidence.
No issue is marked fixed solely from configuration inspection.

Required checks still include clean GNU execution with a different/no system
ICU, pinned musl base images, macOS 15 without Homebrew access, Windows tar and
zip runtime tests, and the constrained ARM/emulated architecture jobs. Other
CPU minima remain experimental until their execution evidence is recorded.

Branch protection still names retired/renamed jobs. Maintainers must update
those required check names when landing #37. Windows ARM64 remains experimental
and is not added to the advertised release matrix by this series.

Attestation signing and draft/public release gates require a real authorized
release run. They have not been exercised by publishing a test release. EDB's
independent archive-signature/checksum limit remains explicit. See
[input verification](input-verification.md) and [the release checklist](support-policy.md).
