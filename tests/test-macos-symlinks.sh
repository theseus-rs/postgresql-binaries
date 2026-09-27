#!/usr/bin/env bash

set -euo pipefail
if [ "$(uname -s)" != Darwin ]; then exit 0; fi
root=$(cd "$(dirname "$0")/.." && pwd)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
mkdir -p "$temporary/external" "$temporary/install/bin"
printf '%s\n' 'int leaf(void) { return 42; }' > "$temporary/leaf.c"
printf '%s\n' 'extern int leaf(void); int answer(void) { return leaf(); }' > "$temporary/answer.c"
printf '%s\n' 'extern int answer(void); int main(void) { return answer() != 42; }' > "$temporary/main.c"
cc -dynamiclib "$temporary/leaf.c" -o "$temporary/external/libleaf.1.2.dylib" \
    -install_name '@loader_path/libleaf.1.dylib'
ln -s libleaf.1.2.dylib "$temporary/external/libleaf.1.dylib"
cc -dynamiclib "$temporary/answer.c" "$temporary/external/libleaf.1.dylib" \
    -o "$temporary/external/libanswer.1.2.dylib" \
    -install_name "$temporary/external/libanswer.1.dylib"
ln -s libanswer.1.2.dylib "$temporary/external/libanswer.1.dylib"
cc "$temporary/main.c" "$temporary/external/libanswer.1.dylib" -o "$temporary/install/bin/probe"
bash "$root/scripts/macos-bundle-deps.sh" "$temporary/install" "$temporary/external"
mv "$temporary/external" "$temporary/hidden"
mv "$temporary/install" "$temporary/relocated"
"$temporary/relocated/bin/probe"
echo 'Requested and transitive dylib names survive symlink resolution and relocation'
