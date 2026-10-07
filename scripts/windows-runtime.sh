#!/usr/bin/env bash

set -eo pipefail
script_directory=$(cd "$(dirname "$0")" && pwd)
source "$script_directory/runtime-common.sh"

windows_readobj() {
    local candidate
    for candidate in "${LLVM_READOBJ:-llvm-readobj}" llvm-readobj-16 '/c/Program Files/LLVM/bin/llvm-readobj.exe'; do
        if command -v "$candidate" >/dev/null 2>&1; then
            "$candidate" --coff-imports "$1"
            return
        fi
    done
    runtime_die 'llvm-readobj is required to audit Windows imports (set LLVM_READOBJ)'
}

windows_imports() {
    local report name
    # LLVM reads both Import and DelayImport directories and rejects malformed
    # PE files. Capture first so a failed audit cannot silently produce no DLLs.
    report=$(windows_readobj "$1") || return 1
    # Read the entire report: grep -q can close the pipe early and make printf
    # fail under pipefail for binaries with many imports, such as StackBuilder.
    printf '%s\n' "$report" | grep -E '^Format: COFF-' >/dev/null || runtime_die "Not a PE/COFF binary: $1"
    while IFS= read -r name; do
        [[ "$name" =~ ^[a-z0-9_.+-]+$ ]] || runtime_die "Invalid imported DLL name: $name"
        printf '%s\n' "$name"
    done < <(printf '%s\n' "$report" | awk '/^  Name: / { sub(/^  Name: /, ""); sub(/\r$/, ""); print tolower($0) }')
}

windows_python_version() {
    local root=$1 file name imports versions=''
    while IFS= read -r -d '' file; do
        imports=$(windows_imports "$file") || return 1
        while IFS= read -r name; do
            if [[ "$name" =~ ^python3([0-9]+)\.dll$ ]]; then
                versions="$versions$(printf '3.%s\n' "${BASH_REMATCH[1]}")"$'\n'
            fi
        done <<< "$imports"
    done < <(find "$root/lib" -type f -iname '*plpython*.dll' -print0)
    versions=$(printf '%s' "$versions" | sed '/^$/d' | sort -u)
    [[ "$versions" =~ ^3\.[0-9]+$ ]] || runtime_die "Expected one Python ABI, found: $versions"
    printf '%s\n' "$versions"
}

windows_system_library() {
    local name=${1%.dll}
    name=${name%.drv}
    case "$name" in
        api-ms-win-*|ext-ms-win-*|vcruntime140*|msvcp140*) return 0 ;;
    esac
    local system=' kernel32 user32 advapi32 bcrypt ncrypt secur32 shell32 shlwapi crypt32 cryptbase normaliz winmm winspool rpcrt4 netapi32 iphlpapi dbghelp psapi imm32 usp10 dwmapi mswsock winhttp ws2_32 wsock32 ntdll ole32 oleaut32 comdlg32 gdi32 msvcrt ucrtbase version powrprof setupapi dnsapi wldap32 hid comctl32 cabinet userenv authz wintrust imagehlp shcore pdh delayimp avrt msimg32 oleacc uxtheme propsys '
    [[ "$system" = *" $name "* ]]
}

windows_audit() {
    local root=$1 output=$2 binary imports name directory found match
    find "$root" -type f \( -iname '*.exe' -o -iname '*.dll' -o -iname '*.pyd' \) -print0 > "$temporary/binaries"
    while IFS= read -r -d '' binary; do
        imports=$(windows_imports "$binary") || return 1
        while IFS= read -r name; do
            [ -n "$name" ] || continue
            if windows_system_library "$name"; then continue; fi
            found=false
            for directory in "${binary%/*}" "$root/bin" "$root/bin/DLLs"; do
                [ -d "$directory" ] || continue
                match=$(find "$directory" -maxdepth 1 -type f -iname "$name" -print -quit)
                if [ -n "$match" ]; then found=true; break; fi
            done
            [ "$found" = true ] || runtime_die "Unbundled DLL $name imported by $binary"
        done <<< "$imports"
        jq -cn --arg file "${binary#"$root/"}" '$file' >> "$output"
    done < "$temporary/binaries"
}

windows_bundle() {
    local root=$1 provider=${2:-edb} prefix expected version destination path directory
    local input_source='EDB input archive'
    prefix=${WINDOWS_PYTHON_ROOT:-${pythonLocation:-}}
    [ -n "$prefix" ] || runtime_die 'Set WINDOWS_PYTHON_ROOT or use actions/setup-python'
    if command -v cygpath >/dev/null 2>&1; then prefix=$(cygpath -u "$prefix"); fi
    prefix=$(cd "$prefix" && pwd -P)
    version=$(awk '$1 == "#define" && $2 == "PY_VERSION" { gsub(/"/, "", $3); print $3 }' "$prefix/include/patchlevel.h")
    if [ "$provider" = source ] && [ -z "$(find "$root/lib" -type f -iname '*plpython*.dll' -print -quit)" ]; then
        # PostgreSQL 14 source builds disable PL/Python. Keep the selected
        # interpreter's runtime without requiring a PL/Python import to inspect.
        expected=${version%.*}
    else
        expected=$(windows_python_version "$root")
    fi
    [[ "$version" = "$expected."* ]] || runtime_die 'Selected Python does not match imported DLL'
    if [ "$provider" = source ]; then input_source='PostgreSQL source build and vcpkg'; fi
    [ -f "$prefix/python${expected//./}.dll" ] || runtime_die 'Missing matching Python runtime DLL'
    destination="$root/bin"
    runtime_copy_stdlib "$prefix/Lib" "$destination/Lib"
    mkdir -p "$destination/DLLs"
    cp -pR "$prefix/DLLs/." "$destination/DLLs/"
    : > "$temporary/bundled"
    : > "$temporary/audited"
    find "$root" -type f -iname '*.dll' ! -iname '*plperl*' ! -iname '*pltcl*' -print0 > "$temporary/dlls"
    while IFS= read -r -d '' path; do
        jq -cn --arg file "${path#"$root/"}" --arg source "$input_source" --arg digest "$(runtime_sha256 "$path")" \
            '{file: $file, source: $source, input_sha256: $digest}' >> "$temporary/bundled"
    done < "$temporary/dlls"
    for path in "$prefix"/python*.dll "$prefix/python.exe"; do
        [ -f "$path" ] || runtime_die "Missing Python runtime file: $path"
        cp -p "$path" "$destination/${path##*/}"
        jq -cn --arg file "bin/${path##*/}" --arg source "$path" --arg version "$version" \
            --arg digest "$(runtime_sha256 "$path")" \
            '{file: $file, source: $source, input_sha256: $digest, package: "CPython", package_version: $version}' >> "$temporary/bundled"
    done
    mkdir -p "$root/dependency-notices/python"
    cp -p "$prefix/LICENSE.txt" "$root/dependency-notices/python/LICENSE.txt"
    for directory in "$root/lib" "$root/lib/postgresql" "$root/share/extension" "$root/share/postgresql/extension"; do
        [ -d "$directory" ] || continue
        find "$directory" -maxdepth 1 -type f \( -iname '*plperl*' -o -iname '*pltcl*' \) -exec rm -f {} +
    done
    if [ "$provider" = source ]; then
        [ -f "$root/COPYRIGHT" ] || runtime_die 'Missing PostgreSQL redistribution notice'
        [ -d "${VCPKG_INSTALLED:-}/share" ] || runtime_die 'Set VCPKG_INSTALLED to collect dependency notices'
        find "$VCPKG_INSTALLED/share" -mindepth 2 -maxdepth 2 -type f -name copyright -print0 > "$temporary/notices"
        [ -s "$temporary/notices" ] || runtime_die 'Missing vcpkg redistribution notices'
        while IFS= read -r -d '' path; do
            directory=${path%/*}
            directory="$root/dependency-notices/vcpkg/${directory##*/}"
            mkdir -p "$directory"
            cp -p "$path" "$directory/copyright"
        done < "$temporary/notices"
    else
        local notices=(server_license.txt commandlinetools_3rd_party_licenses.txt)
        if [ -f "$destination/stackbuilder.exe" ]; then notices+=(StackBuilder_3rd_party_licenses.txt); fi
        for path in "${notices[@]}"; do
            [ -f "$root/$path" ] || runtime_die "Missing EDB redistribution notice: $path"
        done
    fi
    windows_audit "$root" "$temporary/audited"
    jq -n --slurpfile bundled "$temporary/bundled" --slurpfile audited "$temporary/audited" \
        --arg version "$version" --arg abi "$expected" '{bundled: $bundled, audited_files: $audited,
            system: ["Windows", "Microsoft Visual C++ runtime (vcruntime140 family)"],
            missing_notices: [], disabled_features: ["Perl", "Tcl"],
            python_input: {version: $version, provider: "actions/setup-python hosted toolcache", abi: $abi}}' \
        > "$root/runtime-dependencies.json"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    operation=${1:?Usage: windows-runtime.sh <prepare|detect|bundle|bundle-source|imports|audit> <path>}
    root=${2:?Missing path}
    temporary=$(mktemp -d)
    trap 'rm -rf "$temporary"' EXIT
    case "$operation" in
        prepare) cp -p "$root/server_license.txt" "$root/COPYRIGHT" ;;
        detect) version=$(windows_python_version "$root"); printf 'version=%s\n' "$version" ;;
        imports) windows_imports "$root" ;;
        audit) windows_audit "$root" "$temporary/audited" ;;
        bundle) windows_bundle "$(cd "$root" && pwd -P)" ;;
        bundle-source) windows_bundle "$(cd "$root" && pwd -P)" source ;;
        *) runtime_die "Unknown operation: $operation" ;;
    esac
fi
