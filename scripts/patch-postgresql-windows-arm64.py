#!/usr/bin/env python3
"""Backport PostgreSQL's native MSVC ARM64 support to released sources."""

from pathlib import Path
import sys


def replace_once(path: Path, old: str, new: str) -> bool:
    text = path.read_text(encoding="utf-8")

    if new in text:
        return False
    if old not in text:
        raise RuntimeError(f"Unable to patch {path}; missing pattern: {old!r}")

    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    return True


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"Usage: {sys.argv[0]} <postgresql-source-directory>")

    source_directory = Path(sys.argv[1])
    if not source_directory.is_dir():
        raise SystemExit(f"PostgreSQL source directory does not exist: {source_directory}")

    changed: set[Path] = set()

    def patch(relative_path: str, old: str, new: str) -> None:
        path = source_directory / relative_path
        if replace_once(path, old, new):
            changed.add(path)

    # Backport PostgreSQL commit a516b3f00d (MSVC: Support building for
    # AArch64). Released PostgreSQL 16-18 sources predate this fix.
    gendef_path = (
        "src/tools/msvc/gendef.pl"
        if (source_directory / "src/tools/msvc/gendef.pl").exists()
        else "src/tools/msvc_gendef.pl"
    )
    patch(
        gendef_path,
        "# Strip the leading underscore for win32, but not x64",
        "# Strip the leading underscore for win32, but not x64 and aarch64",
    )
    patch(
        gendef_path,
        'unless ($arch eq "x86_64");',
        'unless ($arch eq "x86_64" || $arch eq "aarch64");',
    )
    patch(
        gendef_path,
        '. "    arch: x86 | x86_64\\n"',
        '. "    arch: x86 | x86_64 | aarch64\\n"',
    )
    patch(
        gendef_path,
        "unless ($arch eq 'x86' || $arch eq 'x86_64');",
        "unless ($arch eq 'x86' || $arch eq 'x86_64' || $arch eq 'aarch64');",
    )

    patch(
        "src/include/storage/s_lock.h",
        '''/* If using Visual C++ on Win64, inline assembly is unavailable.
 * Use a _mm_pause intrinsic instead of rep nop.
 */
#if defined(_WIN64)
static __forceinline void
spin_delay(void)
{
\t_mm_pause();
}
#else''',
        '''#ifdef _M_ARM64
static __forceinline void
spin_delay(void)
{
\t/*
\t * Research indicates ISB is better than __yield() on AArch64.  See
\t * https://postgr.es/m/1c2a29b8-5b1e-44f7-a871-71ec5fefc120%40app.fastmail.com.
\t */
\t__isb(_ARM64_BARRIER_SY);
}
#elif defined(_WIN64)
static __forceinline void
spin_delay(void)
{
\t/*
\t * If using Visual C++ on Win64, inline assembly is unavailable.
\t * Use a _mm_pause intrinsic instead of rep nop.
\t */
\t_mm_pause();
}
#else''',
    )
    patch(
        "src/include/storage/s_lock.h",
        '''#include <intrin.h>
#pragma intrinsic(_ReadWriteBarrier)

#define S_UNLOCK(lock)\t\\
\tdo { _ReadWriteBarrier(); (*(lock)) = 0; } while (0)

#endif''',
        '''#include <intrin.h>

#ifdef _M_ARM64

/* _ReadWriteBarrier() is insufficient on non-TSO architectures. */
#pragma intrinsic(_InterlockedExchange)
#define S_UNLOCK(lock) _InterlockedExchange(lock, 0)

#else

#pragma intrinsic(_ReadWriteBarrier)
#define S_UNLOCK(lock)\t\\
\tdo { _ReadWriteBarrier(); (*(lock)) = 0; } while (0)

#endif
#endif''',
    )
    patch(
        "meson.build",
        "  if cc.links(prog, name: '__crc32cb, __crc32ch, __crc32cw, and __crc32cd without -march=armv8-a+crc',\n"
        "      args: test_c_args)",
        "  # Vendor-supported versions of Windows for AArch64 require at least ARMv8.1,\n"
        "  # which is where CRC extension support became mandatory. Thus, use it\n"
        "  # unconditionally on MSVC/AArch64.\n"
        "  if (host_cpu == 'aarch64' and cc.get_id() == 'msvc') or \\\n"
        "        cc.links(prog, name: '__crc32cb, __crc32ch, __crc32cw, and __crc32cd without -march=armv8-a+crc',\n"
        "      args: test_c_args)",
    )
    patch(
        "src/port/pg_crc32c_armv8.c",
        "#include <arm_acle.h>",
        "#ifdef _MSC_VER\n#include <intrin.h>\n#else\n#include <arm_acle.h>\n#endif",
    )

    if changed:
        for path in sorted(changed):
            print(f"Patched {path.relative_to(source_directory)}")
    else:
        print("PostgreSQL source already contains the MSVC ARM64 support patch")


if __name__ == "__main__":
    main()
