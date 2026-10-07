#!/usr/bin/env bash

set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
helper="$root/scripts/windows-runtime.sh"

write_bytes() { printf '%b' "$3" | dd of="$1" bs=1 seek="$2" conv=notrunc 2>/dev/null; }
write_u32() {
    local value=$3 bytes='' octal i
    for ((i=0; i<4; i++)); do
        printf -v octal '\\%03o' "$((value & 255))"
        bytes="$bytes$octal"
        value=$((value >> 8))
    done
    write_bytes "$1" "$2" "$bytes"
}
pe_with_import() {
    local path=$1 name=$2 delay=${3:-}
    dd if=/dev/zero of="$path" bs=1024 count=1 2>/dev/null
    write_bytes "$path" 0 'MZ'
    write_u32 "$path" 60 128
    write_bytes "$path" 128 'PE\000\000\144\206\001\000'
    write_bytes "$path" 148 '\360\000\042\040\013\002'
    write_u32 "$path" 260 16
    write_u32 "$path" 272 4096
    write_u32 "$path" 276 40
    write_bytes "$path" 392 '.rdata\000\000'
    write_u32 "$path" 400 512
    write_u32 "$path" 404 4096
    write_u32 "$path" 408 512
    write_u32 "$path" 412 512
    write_u32 "$path" 524 4352
    write_u32 "$path" 528 4480
    write_bytes "$path" 768 "$name\000"
    if [ -n "$delay" ]; then
        write_u32 "$path" 368 4224
        write_u32 "$path" 372 64
        write_u32 "$path" 640 1
        write_u32 "$path" 644 4416
        write_u32 "$path" 652 4480
        write_u32 "$path" 656 4480
        write_bytes "$path" 832 "$delay\000"
    fi
}

mkdir -p "$temporary/install/lib" "$temporary/install/bin/DLLs" "$temporary/install/share/extension"
install="$temporary/install"
printf 'PostgreSQL server terms\r\n' > "$install/server_license.txt"
bash "$helper" prepare "$install"
printf 'Repository license\n' > "$install/LICENSE"
cmp "$install/server_license.txt" "$install/COPYRIGHT"
mkdir "$temporary/missing"
if bash "$helper" prepare "$temporary/missing" > /dev/null 2>&1; then exit 1; fi
pe_with_import "$install/lib/plpython3.dll" PYTHON313.dll missing.dll
imports=$(bash "$helper" imports "$install/lib/plpython3.dll")
test "$imports" = $'python313.dll\nmissing.dll'
test "$(bash "$helper" detect "$install")" = version=3.13
pe_with_import "$install/lib/other_plpython.dll" python314.dll
if bash "$helper" detect "$install" > /dev/null 2>&1; then exit 1; fi
rm "$install/lib/other_plpython.dll"
pe_with_import "$temporary/invalid.dll" ../python313.dll
if bash "$helper" imports "$temporary/invalid.dll" > /dev/null 2>&1; then exit 1; fi
printf 'truncated' > "$temporary/broken.dll"
if bash "$helper" imports "$temporary/broken.dll" > /dev/null 2>&1; then exit 1; fi
# Normal imports are satisfied; a missing delay-loaded DLL must still fail.
pe_with_import "$install/bin/python313.dll" kernel32.dll
if bash "$helper" audit "$install" > "$temporary/audit.log" 2>&1; then exit 1; fi
grep -q 'Unbundled DLL missing.dll' "$temporary/audit.log"
pe_with_import "$install/bin/DLLs/missing.dll" kernel32.dll
bash "$helper" audit "$install"
# Exercise a complete toolcache-style installation, including stdlib and notices.
prefix="$temporary/python"
mkdir -p "$prefix/include" "$prefix/Lib/site-packages" "$prefix/DLLs"
printf '#define PY_VERSION "3.13.9"\n' > "$prefix/include/patchlevel.h"
printf 'Python license\n' > "$prefix/LICENSE.txt"
printf 'stdlib fixture\n' > "$prefix/Lib/os.py"
printf 'excluded\n' > "$prefix/Lib/site-packages/extra.py"
pe_with_import "$prefix/python313.dll" kernel32.dll
pe_with_import "$prefix/python.exe" python313.dll
pe_with_import "$prefix/DLLs/_ssl.pyd" crypt32.dll
# CPython's _wmi module imports the Windows Property System and delay-loads COM.
pe_with_import "$prefix/DLLs/_wmi.pyd" PROPSYS.dll ole32.dll
printf 'EDB dependency terms\n' > "$install/commandlinetools_3rd_party_licenses.txt"
WINDOWS_PYTHON_ROOT="$prefix" bash "$helper" bundle "$install"
test -f "$install/bin/Lib/os.py"
test ! -e "$install/bin/Lib/site-packages"
test -f "$install/bin/DLLs/_ssl.pyd"
test -f "$install/bin/DLLs/_wmi.pyd"
test ! -e "$install/bin/DLLs/propsys.dll"
cmp "$prefix/LICENSE.txt" "$install/dependency-notices/python/LICENSE.txt"
jq -e '.python_input.abi == "3.13" and .python_input.version == "3.13.9" and
    (.audited_files | index("bin/DLLs/_ssl.pyd") != null) and
    (.audited_files | index("bin/DLLs/_wmi.pyd") != null) and (.missing_notices | length == 0)' \
    "$install/runtime-dependencies.json" >/dev/null
# Large valid LLVM reports must not fail because a format check closes its
# input early. Model a large import table without depending on pipe capacity.
cat > "$temporary/large-readobj" <<'SCRIPT'
#!/usr/bin/env bash
printf 'Format: COFF-x86-64\n'
awk 'BEGIN { for (i = 0; i < 20000; i++) print "  Symbol: fixture_symbol (0)" }'
printf 'Import {\n  Name: KERNEL32.dll\n}\n'
SCRIPT
chmod +x "$temporary/large-readobj"
imports=$(LLVM_READOBJ="$temporary/large-readobj" bash "$helper" imports "$install/bin/python313.dll")
test "$imports" = kernel32.dll
echo 'Windows license, ABI, normal/delay imports, malformed PE and bundled runtime checks passed'
