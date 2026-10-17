# Binary support and release policy

This is a community-maintained distribution, not a vendor support contract.
It does not promise that every historical minor builds with today's compilers.

## Support tiers and environment baselines

| Family | Build/test baseline | Required host ABI | CPU baseline / evidence limit |
| --- | --- | --- | --- |
| Linux GNU | Debian 12.4 base; i586 and ARMv6 hard-float use Buildroot source builds with pinned glibc 2.36 | glibc 2.36 and matching ELF loader | Explicit flags and constrained QEMU models in `targets.json`; CPU minima require passing execution evidence |
| Linux musl (distro builds) | Alpine 3.19.0 base; distro package updates recorded | musl 1.2.4 and matching dynamic ELF loader | Constrained QEMU tests; dynamically linked |
| Linux musl (i586 / ARMv6 soft-float) | Buildroot 2026.08 source builds of libc and dependencies; matching minimal runtime images | Buildroot musl version recorded in each artifact and matching dynamic ELF loader | Pentium without SSE; ARM1176 with VFP disabled; dynamically linked |
| macOS ARM64 / x64 | macOS 15 CI with deployment target 15.0 | macOS system frameworks and libSystem | ARM64 / x86_64; older macOS is not certified |
| Windows x64 | Native `windows-latest` CI; PostgreSQL source build with MSVC and vcpkg dependencies | Windows and Microsoft Visual C++ runtime (`vcruntime140` family) | x64; relocated tar and zip archives tested on that runner; no older Windows minimum is certified |
| Windows ARM64 | Native `windows-11-arm` CI; PostgreSQL 16–18 source build with MSVC and vcpkg dependencies | Windows ARM64 and Microsoft Visual C++ runtime (`vcruntime140` family) | ARM64; relocated tar and zip archives tested on that runner; no older Windows minimum is certified |

## Feature matrix

The following is the intended source-build matrix.
Windows x64 supports PostgreSQL 14–18; Windows ARM64 supports 16–18. "All" means
all supported majors for that platform.

| Feature | GNU 14–18 | musl 14–18 | macOS 14–18 | Windows source builds |
| --- | --- | --- | --- | --- |
| ICU, OpenSSL, XML/XSLT, LZ4 | All | All | All | All |
| readline | All | All | All | Disabled |
| Zstandard | 16–18 | 16–18 | 16–18 | 16–18 |
| PL/Python plus standard library | 15–18 | 15–18 | 15–18 | 15–18 on x64; 16–18 on ARM64; matching CPython ABI bundled |
| LLVM JIT | Disabled | 16–18 | 16–18 | Disabled |
| PostgreSQL timezone database | All | All | All | All |
| LDAP | Disabled | Disabled | Disabled | Disabled |
| Perl / Tcl PostgreSQL extensions | Disabled | Disabled | Disabled | Disabled |

Full upstream regression suites and every optional extension are not covered.

## Updates, EOL and packaging revisions

Follow [PostgreSQL's upstream support dates](https://www.postgresql.org/support/versioning/).
Remove a major from active build/support policy at upstream EOL; retain old
immutable downloads for reproducibility, clearly without ongoing security fixes.
PostgreSQL 14 reaches EOL on November 12, 2026. Adding a new major requires all
feature and platform checks; beta releases are not automatically enabled.

Versions are `<upstream major>.<upstream minor>.<packaging revision>`. Increment
the final component for a confirmed packaging fix, dependency refresh or target
change without an upstream PostgreSQL version change. Never overwrite assets
or reuse an existing tag.

## Release checklist

1. Confirm upstream version/EOL, TLS-verified source revision/digests, action and
   image pins, package inventory, vulnerability review and dependency notices.
2. Run CI for all enabled targets and current supported majors. Resolve
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
