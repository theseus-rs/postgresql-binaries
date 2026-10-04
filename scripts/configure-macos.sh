#!/usr/bin/env bash

set -euo pipefail
: "${VERSION:?VERSION is required}"
# Hosted Intel runners preinstall Python framework symlinks in /usr/local.
# Overwrite those links while retaining the installed framework files.
# Install LLVM's Python dependency explicitly so --overwrite also applies to it.
brew install --overwrite python@3.12
brew install --overwrite fop jq icu4c libxml2 libxslt llvm@16 lz4 openssl@3 pkgconf python@3.13 readline zstd
cppflags=""
ldflags=""
pkg_config_path=""
for formula in icu4c libxml2 libxslt lz4 openssl@3 readline zstd; do
    prefix=$(brew --prefix "$formula")
    cppflags="$cppflags -I$prefix/include"
    ldflags="$ldflags -L$prefix/lib"
    pkg_config_path="$prefix/lib/pkgconfig${pkg_config_path:+:$pkg_config_path}"
done
# Export to callers that source this helper, including local builds.
export CPPFLAGS="$cppflags"
export LDFLAGS="$ldflags"
export PKG_CONFIG_PATH="$pkg_config_path"
export LLVM_CONFIG="$(brew --prefix llvm@16)/bin/llvm-config"
export CLANG="$(brew --prefix llvm@16)/bin/clang"
export PYTHON="$(brew --prefix python@3.13)/bin/python3.13"
export MACOSX_DEPLOYMENT_TARGET=15.0
if [ -n "${GITHUB_ENV:-}" ]; then
    for variable in CPPFLAGS LDFLAGS PKG_CONFIG_PATH LLVM_CONFIG CLANG PYTHON MACOSX_DEPLOYMENT_TARGET; do
        printf '%s=%s\n' "$variable" "${!variable}"
    done >> "$GITHUB_ENV"
fi
