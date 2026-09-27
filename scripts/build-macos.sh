#!/usr/bin/env bash

set -euo pipefail
script_directory=$(cd "$(dirname "$0")" && pwd)
source "$script_directory/macos-options.sh"
cd "$SOURCE_DIRECTORY"
./configure "${configure_options[@]}"
make -j "${MAKE_JOBS:-$(sysctl -n hw.logicalcpu)}" "$build_target"
make "$install_target"
make -C contrib install
cp COPYRIGHT source-input.json "$INSTALL_DIRECTORY"

# Check the generated configuration, not just the requested command line.
for feature in USE_ICU USE_LZ4 USE_OPENSSL USE_LIBXML USE_LIBXSLT; do
    grep -q "^#define $feature 1$" src/include/pg_config.h
done
if [ "$major_version" -ge 15 ]; then
    find "$INSTALL_DIRECTORY/lib" -type f \( -name plpython3.so -o -name plpython3.dylib \) | grep -q .
fi
if [ "$major_version" -ge 16 ]; then
    grep -q '^#define USE_LLVM 1$' src/include/pg_config.h
    grep -q '^#define USE_ZSTD 1$' src/include/pg_config.h
fi
