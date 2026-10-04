#!/usr/bin/env bash

# Bundle executables, extension modules and their transitive dependencies.
# Indexed arrays keep this compatible with macOS's Bash 3.2.
set -eo pipefail
script_directory=$(cd "$(dirname "$0")" && pwd)
source "$script_directory/runtime-common.sh"
root=$(cd "${1:?Usage: bundle-runtime.sh <install_directory>}" && pwd -P)
library_dir="$root/lib"
mkdir -p "$library_dir"
format=elf
if [ "$(uname -s)" = Darwin ]; then format=macho; fi
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
: > "$temporary/bundled"
: > "$temporary/system"
: > "$temporary/audited"
queue=() processed=() destinations=() origins=() initial_names=() initial_files=()
stdlib='' installed_stdlib=''

scan_binaries() {
    local file
    find "$root" -type f -print0 > "$temporary/files"
    queue=()
    while IFS= read -r -d '' file; do
        if runtime_is_binary "$file" "$format"; then queue+=("$file"); fi
    done < "$temporary/files"
    [ "${#queue[@]}" -gt 0 ] || runtime_die 'No installed binaries to audit'
}

scan_binaries
for file in "${queue[@]}"; do
    if [[ "${file##*/}" = plpython* ]]; then
        # Resolve the configured interpreter's symlink to its base installation;
        # the executable name identifies its version without a Python helper.
        interpreter=$(command -v "${PYTHON:-python3}")
        interpreter=$(runtime_realpath "$interpreter")
        prefix=$(dirname "$(dirname "$interpreter")")
        python_name=${interpreter##*/}
        [[ "$python_name" =~ ^python(3\.[0-9]+)$ ]] || runtime_die "Cannot identify Python ABI: $interpreter"
        stdlib="$prefix/lib/$python_name"
        [ -f "$stdlib/os.py" ] || runtime_die "Missing Python standard library: $stdlib"
        installed_stdlib="$library_dir/$python_name"
        runtime_copy_stdlib "$stdlib" "$installed_stdlib"
        scan_binaries
        break
    fi
done
for file in "${queue[@]}"; do
    if [ "${file%/*}" = "$library_dir" ]; then
        initial_names+=("${file##*/}")
        initial_files+=("$file")
    fi
done
search=("$library_dir" /lib /usr/lib /usr/local/lib)
for directory in /lib/*-linux-* /usr/lib/*-linux-* /usr/lib/llvm*/lib; do
    [ ! -d "$directory" ] || search+=("$directory")
done

resolve_dependency() {
    local name=$1 binary=$2 tail rpath candidate i
    if [ "$format" = macho ]; then
        case "$name" in
            @loader_path/*) printf '%s/%s\n' "${binary%/*}" "${name#@loader_path/}" ;;
            @executable_path/*) printf '%s/bin/%s\n' "$root" "${name#@executable_path/}" ;;
            @rpath/*)
                tail=${name#@rpath/}
                otool -l "$binary" > "$temporary/load-commands"
                while IFS= read -r rpath; do
                    rpath=${rpath//@loader_path/${binary%/*}}
                    rpath=${rpath//@executable_path/$root\/bin}
                    if [ -f "$rpath/$tail" ]; then printf '%s\n' "$rpath/$tail"; return; fi
                done < <(awk '/cmd LC_RPATH/ { found=1; next } found && /path / { sub(/^[[:space:]]*path /, ""); sub(/ \(offset.*$/, ""); print; found=0 }' "$temporary/load-commands")
                # Homebrew ICU also uses @rpath for sibling libraries without
                # an LC_RPATH in the importing dylib.
                if [ -f "${binary%/*}/$tail" ]; then printf '%s\n' "${binary%/*}/$tail"; return; fi
                [ -f "$library_dir/$tail" ] || runtime_die "Unresolved $name in $binary"
                printf '%s\n' "$library_dir/$tail"
                ;;
            *) printf '%s\n' "$name" ;;
        esac
    else
        for ((i=0; i<${#initial_names[@]}; i++)); do
            if [ "${initial_names[i]}" = "$name" ]; then printf '%s\n' "${initial_files[i]}"; return; fi
        done
        rpath=$(patchelf --print-rpath "$binary")
        local candidates=("${binary%/*}") rpaths=()
        IFS=: read -r -a rpaths <<< "$rpath"
        for candidate in "${rpaths[@]}"; do
            [ -n "$candidate" ] || continue
            candidate=${candidate//\$\{ORIGIN\}/${binary%/*}}
            candidate=${candidate//\$ORIGIN/${binary%/*}}
            candidates+=("$candidate")
        done
        candidates+=("${search[@]}")
        for candidate in "${candidates[@]}"; do
            if [ -f "$candidate/$name" ]; then printf '%s\n' "$candidate/$name"; return; fi
        done
        runtime_die "Unresolved $name in $binary"
    fi
}

index=0
while [ "$index" -lt "${#queue[@]}" ]; do
    binary=${queue[index]}
    index=$((index + 1))
    already=false
    for file in "${processed[@]}"; do
        if [ "$file" = "$binary" ]; then already=true; break; fi
    done
    [ "$already" = false ] || continue
    processed+=("$binary")
    chmod u+w "$binary"
    original=$binary
    for ((i=0; i<${#destinations[@]}; i++)); do
        if [ "${destinations[i]}" = "$binary" ]; then original=${origins[i]}; break; fi
    done
    if [ -n "$installed_stdlib" ] && [[ "$binary" = "$installed_stdlib/"* ]]; then
        original="$stdlib/${binary#"$installed_stdlib/"}"
    fi
    ids=''
    if [ "$format" = macho ]; then
        otool -L "$binary" > "$temporary/otool"
        sed '1d; s/^[[:space:]]*//; s/ (.*$//' "$temporary/otool" > "$temporary/dependencies"
        ids=$(otool -D "$binary" | sed '1d')
    else
        patchelf --print-needed "$binary" > "$temporary/dependencies"
    fi
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        if [ -n "$ids" ] && printf '%s\n' "$ids" | grep -Fxq "$name"; then continue; fi
        if runtime_system_library "$name" "$format"; then
            jq -cn --arg name "$name" '$name' >> "$temporary/system"
            continue
        fi
        source_file=$(resolve_dependency "$name" "$original")
        source_file=$(runtime_realpath "$source_file")
        [ -f "$source_file" ] || runtime_die "Missing $name required by $binary"
        if [[ "$source_file" = "$root/"* ]]; then
            destination=$source_file
        else
            destination="$library_dir/${name##*/}"
            known=false
            for ((i=0; i<${#destinations[@]}; i++)); do
                if [ "${destinations[i]}" = "$destination" ]; then
                    [ "${origins[i]}" = "$source_file" ] || runtime_die "Conflicting libraries named ${destination##*/}"
                    known=true
                    break
                fi
            done
            if [ "$known" = false ]; then
                [ ! -e "$destination" ] || runtime_die "Dependency overwrites installed file: $destination"
                cp -p "$source_file" "$destination"
                destinations+=("$destination")
                origins+=("$source_file")
                queue+=("$destination")
                jq -cn --arg file "${destination#"$root/"}" --arg source "$source_file" \
                    --arg digest "$(runtime_sha256 "$source_file")" \
                    '{file: $file, source: $source, input_sha256: $digest}' >> "$temporary/bundled"
            fi
        fi
        if [ "$format" = macho ]; then
            relative=$(runtime_relative_path "$destination" "${binary%/*}")
            install_name_tool -change "$name" "@loader_path/$relative" "$binary"
        fi
    done < "$temporary/dependencies"
    if [ "$format" = macho ]; then
        if [ -n "$ids" ]; then install_name_tool -id "@loader_path/${binary##*/}" "$binary"; fi
    else
        relative=$(runtime_relative_path "$library_dir" "${binary%/*}")
        patchelf --set-rpath "\$ORIGIN:\$ORIGIN/$relative" "$binary"
    fi
    jq -cn --arg file "${binary#"$root/"}" '$file' >> "$temporary/audited"
done
if [ "$format" = macho ]; then
    for binary in "${processed[@]}"; do
        codesign --force --sign - "$binary"
        otool -L "$binary" > "$temporary/otool"
        while IFS= read -r name; do
            if ! runtime_system_library "$name" macho && [[ "$name" != @loader_path/* ]]; then
                runtime_die "Nonportable load command: $name in $binary"
            fi
        done < <(sed '1d; s/^[[:space:]]*//; s/ (.*$//' "$temporary/otool")
    done
fi
jq -n --slurpfile bundled "$temporary/bundled" --slurpfile system "$temporary/system" \
    --slurpfile audited "$temporary/audited" \
    '{bundled: $bundled, system: ($system | unique), audited_files: ($audited | sort)}' \
    > "$root/runtime-dependencies.json"
