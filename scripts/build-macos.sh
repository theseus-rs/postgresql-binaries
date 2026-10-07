#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <version> <target>" >&2
    exit 1
fi

VERSION="$1"
TARGET="$2"
ROOT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIRECTORY="${INSTALL_DIRECTORY:-$ROOT_DIRECTORY/postgresql-$VERSION-$TARGET}"
SOURCE_DIRECTORY="$ROOT_DIRECTORY/postgresql-src"
script_directory="$ROOT_DIRECTORY/scripts"

cd "$ROOT_DIRECTORY"
"$script_directory/fetch-source.sh" "$VERSION" "$SOURCE_DIRECTORY"
source "$script_directory/configure-macos.sh"
"$PYTHON" "$script_directory/patch-postgresql-libxml2.py" "$SOURCE_DIRECTORY"
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

# Make the installation relocatable and bundle its Homebrew dependencies.
"$script_directory/macos-bundle-deps.sh" "$INSTALL_DIRECTORY" "$(brew --prefix)"
