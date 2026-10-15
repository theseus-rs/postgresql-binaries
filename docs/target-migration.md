# Target validation and migration

New MIPS assets use `mips64el-unknown-linux-gnuabi64`. The previously named
`mips64-unknown-linux-gnuabi64` 18.6.0 asset was inspected on 2026-09-27:
ELF64, little-endian, machine 8, flags `0x80000007` (MIPS64r2/N64). The old name
incorrectly describes big-endian MIPS. Update download URLs and target mappings;
old assets are not renamed or overwritten. Big-endian MIPS is not supported.

The following targets now use Buildroot to build libc and dependencies for
their advertised CPU and ABI instead of using incompatible distro packages:

| Target | Build baseline |
| --- | --- |
| `i586-unknown-linux-gnu` | Pentium/i586, without SSE, with a glibc 2.36 ceiling. |
| `i586-unknown-linux-musl` | Pentium/i586, without SSE. |
| `arm-unknown-linux-musleabi` | ARMv6 soft-float, tested with VFP disabled. |
| `arm-unknown-linux-gnueabihf` | ARMv6 hard-float with VFPv2. |

The [Rust ARM target definitions](https://doc.rust-lang.org/rustc/platform-support/arm-linux.html)
distinguish ARMv6 from ARMv7 and soft/hard-float calling conventions.
[Debian's Bookworm requirements](https://www.debian.org/releases/bookworm/i386/ch02s01.en.html)
exclude i586. A matching ELF machine number alone is insufficient evidence.

Validation checks every ELF executable/module for class, byte order, machine,
float/N64/ELFv2 ABI and interpreter; it records ARM attributes and GNU CPU notes.
Compiler baseline flags are explicit. ARM tests use x86 runners and QEMU CPU
models (arm926, arm1176, cortex-a7, cortex-a53) so an ARM64 host cannot silently bypass CPU
emulation. ARM attributes may include higher-ISA runtime-dispatched routines;
they are retained as evidence rather than treated as proof of minimum CPU.
MIPS, PowerPC and s390x runtime tests likewise request MIPS64R2-generic, power8
and z196 models from the pinned emulator image. x86 Linux builds/tests use ARM
runners so emulation cannot be bypassed by the host kernel: qemu64 with SSE3,
CX16 and LAHF-LM disabled for the x86-64 baseline; qemu32 with SSE3 disabled for
i686/SSE2. These models were checked against the pinned image, including Linux
loader startup for the x86 models. Full archive execution must pass before
promotion; loader startup alone does not establish the CPU minimum.

macOS checks Mach-O architecture and a deployment minimum no newer than 15.0.
Windows checks PE machine types. Windows x64 and ARM64 use source builds and
native runners; ARM64 builds require PostgreSQL 16 or newer. Runtime tests,
archive relocation, input verification, and dependency audits gate publication.
