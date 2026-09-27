# Binary support and release policy

This is a community-maintained distribution, not a vendor support contract.
The September 27, 2026 assessment tracks current PostgreSQL 14–18 minors in
`supported-versions.json`. It does not promise that every historical minor builds
with today's compilers. The daily read-only upstream check reports new versions
and EOL as workflow failures; it never creates tags, issues or releases.

## Support tiers and environment baselines

* Verified: the exact packaging revision has passed its target/ABI audit, clean
  relocated runtime and feature tests, manifest/notices checks, and public-download
  checks. The release checklist must link that evidence.
* Experimental: builds are available for investigation, but CPU/OS/runtime or
  feature coverage is incomplete. No unsupported minimum is implied by the name.
* Quarantined: an incompatible or unverified target alias is disabled in
  `targets.json`; no new release asset is published under that name.

No target is promoted by a configure flag, a file-header match, or this document.
The implementation series remains under validation until its integration run
passes. Native Windows ARM64 work in #27 is separate and is not yet advertised.
Its PostgreSQL 18.6 native smoke test passed, but shared input, dependency and
archive verification changes and the 16/17 native tests remain outstanding.

| Family | Build/test baseline | Required host ABI | CPU baseline / evidence limit |
| --- | --- | --- | --- |
| Linux GNU | Debian 12.4 base; distro package updates recorded | glibc 2.36 and matching ELF loader | Explicit flags and constrained QEMU models in `targets.json`; CPU minima require passing execution evidence |
| Linux musl | Alpine 3.19.0 base; distro package updates recorded | musl 1.2.4 and matching dynamic ELF loader | Constrained QEMU tests; dynamic, not static; i586 and soft-float ARM aliases quarantined |
| macOS ARM64 / x64 | macOS 15 CI with deployment target 15.0 | macOS system frameworks and libSystem | ARM64 / x86_64; older macOS is not certified |
| Windows x64 | GitHub Windows runner recorded in provenance; EDB repackaged archive | EDB-supported Windows and Visual C++ runtime | x64; no independently tested minimum Windows version is promised |

These are candidate/test baselines, not claims that the full new matrix has
already passed. The kernel minimum is not independently established. Host libc
and loader compatibility remains necessary on NixOS. See
[runtime dependencies](runtime-dependencies.md) and [target migration](target-migration.md).

## Feature matrix

The following is the intended source-build matrix; the generated feature record
and runtime tests must confirm it for each artifact.

| Feature | GNU 14–18 | musl 14–18 | macOS 14–18 | EDB Windows |
| --- | --- | --- | --- | --- |
| ICU, OpenSSL, XML/XSLT, LZ4, readline | All | All | All | Recorded from EDB; exercise available extensions |
| Zstandard | 16–18 | 16–18 | 16–18 | Upstream-dependent |
| PL/Python plus standard library | 15–18 | 15–18 | 15–18 | Matching CPython ABI detected and bundled; runtime tests required |
| LLVM JIT | Disabled | 16–18 | 16–18 | Upstream-dependent |
| PostgreSQL timezone database | All | All | All | Archive must contain its timezone files |
| LDAP | Disabled | Disabled | Disabled | Upstream-dependent |
| Perl / Tcl PostgreSQL extensions | Disabled | Disabled | Disabled | Removed because their language runtimes are not bundled |

Core SQL, version/encoding, UTC/named timezone behavior, pgcrypto, xml2, hstore,
ICU collations, LZ4 storage, gzip/Zstandard dump/restore, and enabled Python/JIT
branches are exercised after extraction.
Full upstream regression suites and every optional extension are not covered.

## Updates, EOL and packaging revisions

Follow [PostgreSQL's upstream support dates](https://www.postgresql.org/support/versioning/).
Remove a major from active build/support policy at upstream EOL; retain old
immutable downloads for reproducibility, clearly without ongoing security fixes.
PostgreSQL 14 reaches EOL on November 12, 2026. Adding a new major requires all
feature and platform checks; beta releases are not automatically enabled.

The maintenance target is to triage an upstream security release within three
business days and publish validated verified-tier packages within seven calendar
days, subject to maintainer availability. This is a target, not a guarantee.
If blocked, report affected targets and the reason in release/issue notes;
never publish unchecked binaries to meet the target. Bundled-library security
updates require the same review and runtime validation as PostgreSQL updates.

Versions are `<upstream major>.<upstream minor>.<packaging revision>`. Increment
the final component for a confirmed packaging fix, dependency refresh or target
change without an upstream PostgreSQL version change. Never overwrite assets
or reuse an existing tag. #31 did not reproduce on the freshly tested x64 GNU
18.6.0 asset, so it does not by itself justify a new packaging revision.

## Release checklist

1. Confirm upstream version/EOL, TLS-verified source revision/digests, action and
   image pins, package inventory, vulnerability review and dependency notices.
2. Run Integration for all enabled targets and current supported majors. Resolve
   failures, compare the actual feature manifest, and link CI/CPU evidence. Update
   branch-protection check names when a target is renamed or retired.
3. Review `source-input.json`, build/runtime/target records, archive manifests,
   SBOMs and standard checksums. Validate relocated archives in clean environments
   and verify both Windows tar and zip archives.
4. Obtain maintainer review of a concrete release candidate. Create a new tag only
   after approval. The release workflow verifies tested/uploaded digest continuity
   and the complete signed draft inventory before publishing.
5. Require the separate public-download runtime/attestation checks to succeed.
   A failure after publication remains visible; investigate and document it,
   then propose a new packaging revision if warranted. Do not replace assets.

Consumers can reproduce integrity/provenance checks using the commands in
[provenance](provenance.md), then run `bin/postgres --version` and
`SHOW server_version_num` against the actual executable/server they use. The
packaging revision is not part of PostgreSQL's reported server version.
