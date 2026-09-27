# Target validation and migration

New MIPS assets use `mips64el-unknown-linux-gnuabi64`. The previously named
`mips64-unknown-linux-gnuabi64` 18.6.0 asset was inspected on 2026-09-27:
ELF64, little-endian, machine 8, flags `0x80000007` (MIPS64r2/N64). The old name
incorrectly describes big-endian MIPS. Update download URLs and target mappings;
old assets are not renamed or overwritten. Big-endian MIPS is not supported.

The following misleading aliases are quarantined from new builds/releases in
`targets.json`, pending a compatible toolchain/dependency set and CPU tests:

| Old target | Migration / limitation |
| --- | --- |
| `i586-unknown-linux-gnu` | Use `i686-unknown-linux-gnu` on i686/SSE2 hosts. Debian 12 does not support Pentium/i586. |
| `i586-unknown-linux-musl` | Use `i686-unknown-linux-musl` on i686/SSE2 hosts. No original-Pentium dependency/CPU validation exists. |
| `arm-unknown-linux-musleabi` | The old archive is hard-float: EABI flags `0x5000400`, `/lib/ld-musl-armhf.so.1`. It cannot run as soft-float. Use a hard-float target only on a compatible host. |
| `arm-unknown-linux-gnueabihf` | Use `armv7-unknown-linux-gnueabihf` on ARMv7 hosts. Debian armhf dependencies cannot establish the ARMv6 baseline implied by the old alias. |

The [Rust ARM target definitions](https://doc.rust-lang.org/rustc/platform-support/arm-linux.html)
distinguish ARMv6 from ARMv7 and soft/hard-float calling conventions.
[Debian's Bookworm requirements](https://www.debian.org/releases/bookworm/i386/ch02s01.en.html)
exclude i586. A matching ELF machine number alone is insufficient evidence.

Validation checks every ELF executable/module for class, byte order, machine,
float/N64/ELFv2 ABI and interpreter; it records ARM attributes and GNU CPU notes.
Compiler baseline flags are explicit. ARM32 tests use x86 runners and QEMU CPU
models (arm926, arm1176, cortex-a7) so an ARM64 host cannot silently bypass CPU
emulation. ARM attributes may include higher-ISA runtime-dispatched routines;
they are retained as evidence rather than treated as proof of minimum CPU.
Non-ARM CPU minima still require hardware/emulator execution before promotion.

macOS checks Mach-O architecture and a deployment minimum no newer than 15.0.
Windows checks PE machine types. [PR #27](https://github.com/theseus-rs/postgresql-binaries/pull/27)
retains its contributor commits and native Windows ARM64 work separately. It
introduces source builds, dependency installation and source patches beyond a
target-row addition. Windows ARM64 is not advertised by this series until its
native runner tests, archive relocation, input verification, dependencies and
notices have been reconciled. Do not substitute x64 emulation as native evidence.

Branch protection currently names retired/renamed build jobs (including the old
MIPS name and ARM runners). Maintainers must update required check names when
landing this change; the implementation does not bypass or modify protection.
