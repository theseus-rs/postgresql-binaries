#!/usr/bin/env bash

set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
export SOURCE_DIRECTORY=/source INSTALL_DIRECTORY='/install with spaces'
for major in 14 15 16 17 18; do
    export VERSION="$major.0.0"
    source "$root/scripts/macos-options.sh"
    test "$major_version" = "$major"
    test "${configure_options[1]}" = "$INSTALL_DIRECTORY"
    flags=" ${configure_options[*]} "
    [[ "$flags" == *' --with-icu '* && "$flags" == *' --with-lz4 '* ]]
    if [ "$major" -ge 15 ]; then
        [[ "$flags" == *' --with-python '* ]]
        test "$install_target" = install-world-bin
    else
        [[ "$flags" != *' --with-python '* ]]
        test "$install_target" = install
    fi
    if [ "$major" -ge 16 ]; then
        [[ "$flags" == *' --with-llvm '* && "$flags" == *' --with-zstd '* ]]
    else
        [[ "$flags" != *' --with-llvm '* && "$flags" != *' --with-zstd '* ]]
    fi
    if [ "$major" -le 16 ]; then
        [[ "$flags" == *' --enable-thread-safety '* ]]
    else
        [[ "$flags" != *' --enable-thread-safety '* ]]
    fi
done
if (unset VERSION; source "$root/scripts/macos-options.sh") 2>/dev/null; then exit 1; fi
if (VERSION=bad; source "$root/scripts/macos-options.sh") 2>/dev/null; then exit 1; fi
echo 'macOS 14–18 option checks passed'
