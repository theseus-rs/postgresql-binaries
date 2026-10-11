#!/usr/bin/env bash

set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
mkdir -p "$temporary/external" "$temporary/install/bin" "$temporary/install/lib/postgresql"
cat > "$temporary/leaf.c" <<'C'
int leaf(void) { return 42; }
C
cat > "$temporary/extension.c" <<'C'
extern int leaf(void);
int answer(void) { return leaf(); }
C
cat > "$temporary/probe.c" <<'C'
#include <dlfcn.h>
#include <stdio.h>
int main(int argc, char **argv) {
    void *module = dlopen(argv[1], RTLD_NOW);
    if (!module) { fprintf(stderr, "%s\n", dlerror()); return 1; }
    int (*answer)(void) = dlsym(module, "answer");
    return !answer || answer() != 42;
}
C
if [ "$(uname -s)" = Darwin ]; then
    cc -dynamiclib "$temporary/leaf.c" -o "$temporary/external/libleaf.1.dylib" -Wl,-install_name,"$temporary/external/libleaf.dylib"
    ln -s libleaf.1.dylib "$temporary/external/libleaf.dylib"
    cc -dynamiclib "$temporary/extension.c" -L"$temporary/external" -lleaf -o "$temporary/install/lib/postgresql/extension.so"
    cc "$temporary/probe.c" -o "$temporary/install/bin/probe"
else
    command -v patchelf >/dev/null
    cc -shared -fPIC "$temporary/leaf.c" -o "$temporary/external/libleaf.so.1.0" -Wl,-soname,libleaf.so.1
    ln -s libleaf.so.1.0 "$temporary/external/libleaf.so.1"
    ln -s libleaf.so.1 "$temporary/external/libleaf.so"
    cc -shared -fPIC "$temporary/extension.c" -L"$temporary/external" -lleaf -Wl,-rpath,"$temporary/external" -o "$temporary/install/lib/postgresql/extension.so"
    cc "$temporary/probe.c" -ldl -o "$temporary/install/bin/probe"
fi
bash "$root/scripts/bundle-runtime.sh" "$temporary/install"
mv "$temporary/external" "$temporary/hidden"
mv "$temporary/install" "$temporary/relocated"
"$temporary/relocated/bin/probe" "$temporary/relocated/lib/postgresql/extension.so"
echo 'Relocated nested module and symlinked dependency passed'

if [ "$(uname -s)" != Darwin ]; then
    # Cross builds must resolve /usr/lib inside their target sysroot, including
    # transitive dependencies, and must reject links escaping to host libraries.
    mkdir -p "$temporary/sysroot/usr/lib" "$temporary/cross/lib/postgresql"
    cp -a "$temporary/hidden/." "$temporary/sysroot/usr/lib/"
    cc -shared -fPIC "$temporary/extension.c" -L"$temporary/sysroot/usr/lib" -lleaf \
        -Wl,-rpath,/usr/lib -o "$temporary/cross/lib/postgresql/extension.so"
    RUNTIME_SYSROOT="$temporary/sysroot" bash "$root/scripts/bundle-runtime.sh" "$temporary/cross"
    mv "$temporary/sysroot/usr/lib" "$temporary/sysroot/hidden"
    "$temporary/relocated/bin/probe" "$temporary/cross/lib/postgresql/extension.so"

    # Installed SONAME symlinks must take precedence over the original sysroot
    # RPATH. PostgreSQL installs libpq.so.5 as a link to its versioned library.
    mkdir -p "$temporary/sysroot/opt/postgresql/lib" "$temporary/installed/lib/postgresql"
    cp -a "$temporary/hidden/." "$temporary/sysroot/opt/postgresql/lib/"
    cp -a "$temporary/sysroot/opt/postgresql/lib/." "$temporary/installed/lib/"
    cc -shared -fPIC "$temporary/extension.c" -L"$temporary/sysroot/opt/postgresql/lib" -lleaf \
        -Wl,-rpath,/opt/postgresql/lib -o "$temporary/installed/lib/postgresql/extension.so"
    RUNTIME_SYSROOT="$temporary/sysroot" bash "$root/scripts/bundle-runtime.sh" "$temporary/installed"
    test -L "$temporary/installed/lib/libleaf.so.1"
    jq -e '.bundled | length == 0' "$temporary/installed/runtime-dependencies.json" >/dev/null
    mv "$temporary/sysroot/opt" "$temporary/sysroot/hidden-opt"
    "$temporary/relocated/bin/probe" "$temporary/installed/lib/postgresql/extension.so"
    echo 'Installed SONAME symlink takes precedence over sysroot RPATH'

    mkdir -p "$temporary/sysroot/usr/lib" "$temporary/escape/lib"
    ln -s "$temporary/hidden/libleaf.so.1.0" "$temporary/sysroot/usr/lib/libleaf.so.1"
    cc -shared -fPIC "$temporary/extension.c" -L"$temporary/hidden" -lleaf \
        -Wl,-rpath,/usr/lib -o "$temporary/escape/lib/extension.so"
    if RUNTIME_SYSROOT="$temporary/sysroot" bash "$root/scripts/bundle-runtime.sh" "$temporary/escape" >"$temporary/escape.log" 2>&1; then
        echo 'An escaping target dependency was accepted' >&2
        exit 1
    fi
    grep -q 'Dependency escapes target sysroot' "$temporary/escape.log"
    echo 'Target sysroot isolation and relocation passed'
fi
