#!/usr/bin/env bash

set -euo pipefail
: "${GITHUB_ENV:?GITHUB_ENV is required}"
: "${VERSION:?VERSION is required}"
brew install fop icu4c libxml2 libxslt llvm@16 lz4 openssl@3 pkgconf python@3.13 readline zstd
cppflags=""
ldflags=""
pkg_config_path=""
for formula in icu4c libxml2 libxslt lz4 openssl@3 readline zstd; do
    prefix=$(brew --prefix "$formula")
    cppflags="$cppflags -I$prefix/include"
    ldflags="$ldflags -L$prefix/lib"
    pkg_config_path="$prefix/lib/pkgconfig${pkg_config_path:+:$pkg_config_path}"
done
{
    echo "CPPFLAGS=$cppflags"
    echo "LDFLAGS=$ldflags"
    echo "PKG_CONFIG_PATH=$pkg_config_path"
    echo "LLVM_CONFIG=$(brew --prefix llvm@16)/bin/llvm-config"
    echo "CLANG=$(brew --prefix llvm@16)/bin/clang"
    echo "PYTHON=$(brew --prefix python@3.13)/bin/python3.13"
    echo "MACOSX_DEPLOYMENT_TARGET=15.0"
} >> "$GITHUB_ENV"
