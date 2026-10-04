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
