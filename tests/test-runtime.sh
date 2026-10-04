#!/usr/bin/env bash

set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
source "$root/scripts/runtime-common.sh"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
printf '\177ELF\002\001\001\000\000\000\000\000\000\000\000\000\001\000\000\000' > "$temporary/python.o"
if runtime_is_binary "$temporary/python.o"; then exit 1; fi
printf '\003' | dd of="$temporary/python.o" bs=1 seek=16 conv=notrunc 2>/dev/null
runtime_is_binary "$temporary/python.o"
# Big-endian ELF headers must use the other byte of e_type.
printf '\002' | dd of="$temporary/python.o" bs=1 seek=5 conv=notrunc 2>/dev/null
printf '\000\003' | dd of="$temporary/python.o" bs=1 seek=16 conv=notrunc 2>/dev/null
runtime_is_binary "$temporary/python.o"
for name in libc.so.6 libm.so.6 libc.musl-x86_64.so.1 ld-linux-x86-64.so.2; do runtime_system_library "$name"; done
for name in libxml2.so.2 libicuuc.so.72 libssl.so.3 libstdc++.so.6 libpython3.11.so.1.0 libcrypto.so.3; do
    if runtime_system_library "$name"; then exit 1; fi
done
if runtime_system_library /opt/homebrew/opt/openssl/lib/libssl.3.dylib macho; then exit 1; fi
runtime_system_library /usr/lib/libSystem.B.dylib macho
test "$(runtime_relative_path /opt/test/lib /opt/test/lib/postgresql)" = ../
test "$(runtime_relative_path '/opt/test/lib/a b' /opt/test/bin)" = '../lib/a b'
echo 'Runtime binary classification, OS library boundaries and relative paths passed'
