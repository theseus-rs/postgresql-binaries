# Runtime dependencies

Linux packages are dynamically linked, including musl packages. The host must
provide the matching ELF interpreter and libc. GNU builds use Debian 12's glibc
2.36 baseline; musl builds use Alpine 3.19's musl 1.2.4 baseline. NixOS users still
need an ELF interpreter arrangement (for example an appropriate FHS environment).
Bundling timezone data does not remove that requirement.

The bundler scans executables and loadable modules recursively, copies their
non-system library closure, and gives each ELF object a relative RUNPATH. This
includes OpenSSL, XML, ICU where enabled, compression libraries, C++ support, and
Python/LLVM dependencies where enabled. PL/Python also includes its standard
library. macOS libraries use paths relative to their own loader and are signed
again after modification. macOS still requires system frameworks/libSystem.
Windows keeps EDB's dependency and notice files, detects the Python DLL ABI
imported by PL/Python, and bundles a matching CPython runtime/standard library.
Its PE import audit rejects missing non-system DLLs. Unbundled Perl/Tcl modules
are removed to match the Unix feature selection. Windows and the Visual C++
runtime remain host prerequisites.

`runtime-dependencies.json` records original library paths, input digests,
system libraries, and all audited files. `dependency-notices/` preserves
available package/Homebrew notices. Missing notices are explicitly recorded and
block a release; Alpine packages that omit source notices require collection of
their upstream source notices before publication. A passing runtime smoke test
does not discharge this redistribution requirement.

CI extracts archives into a new directory and tests GNU and musl binaries in
base OS containers without installing PostgreSQL's development dependencies.
macOS execution denies access to Homebrew and system timezone directories.
Tests load pgcrypto, xml2, hstore, PL/Python where installed, and LLVM JIT where
installed. These tests establish only the OS/CPU configurations actually run;
they do not prove arbitrary older hosts or CPUs are supported.
