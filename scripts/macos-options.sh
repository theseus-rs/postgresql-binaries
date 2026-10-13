#!/usr/bin/env bash

# Sourced by the build and selection regression checks (Bash 3.2 compatible).
: "${VERSION:?VERSION is required}"
: "${SOURCE_DIRECTORY:?SOURCE_DIRECTORY is required}"
: "${INSTALL_DIRECTORY:?INSTALL_DIRECTORY is required}"
sh "$(dirname "${BASH_SOURCE[0]}")/postgresql-versions.sh" validate "$VERSION" || return 1
major_version="${VERSION%%.*}"
configure_options=(
    --prefix "$INSTALL_DIRECTORY"
    --enable-option-checking=fatal
    --with-icu --without-ldap --with-libxml --with-libxslt
    --with-lz4 --with-openssl --with-pgport=5432 --with-readline
    --with-uuid=e2fs
)
if [ "$major_version" -le 16 ]; then
    configure_options+=(--enable-thread-safety)
fi
build_target=all
install_target=install
if [ "$major_version" -ge 15 ]; then
    configure_options+=(--with-python)
    build_target=world-bin
    install_target=install-world-bin
fi
if [ "$major_version" -ge 16 ]; then
    configure_options+=(--with-llvm --with-zstd)
fi
