#!/usr/bin/env bash

# Shared Bash 3.2-compatible helpers for packaging and runtime audits.
export LC_ALL=C

runtime_die() { printf '%s\n' "$*" >&2; exit 1; }

runtime_sha256() {
    local digest
    if command -v sha256sum >/dev/null 2>&1; then
        digest=$(sha256sum -b < "$1")
    else
        digest=$(shasum -a 256 -b < "$1")
    fi
    digest=${digest%% *}
    [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || runtime_die 'Invalid SHA-256 digest'
    printf '%s\n' "$digest"
}

runtime_realpath() (
    local path=$1 links=0
    while :; do
        cd -P "$(dirname "$path")" || exit 1
        path=$(basename "$path")
        if [ ! -L "$path" ]; then
            printf '%s/%s\n' "$(pwd -P)" "$path"
            exit 0
        fi
        links=$((links + 1))
        [ "$links" -le 40 ] || runtime_die "Too many symbolic links: $1"
        path=$(readlink "$path") || exit 1
    done
)

runtime_relative_path() {
    local destination=$1 base=$2 prefix=''
    while [[ "$destination" != "$base" && "$destination" != "$base/"* ]]; do
        [ "$base" != / ] || break
        base=${base%/*}
        base=${base:-/}
        prefix="../$prefix"
    done
    if [ "$destination" = "$base" ]; then
        printf '%s\n' "${prefix:-.}"
    elif [ "$base" = / ]; then
        printf '%s%s\n' "$prefix" "${destination#/}"
    else
        printf '%s%s\n' "$prefix" "${destination#"$base/"}"
    fi
}

runtime_is_binary() {
    local header magic type
    header=$(od -An -v -tx1 -N20 "$1") || return 1
    # Hex bytes contain no shell metacharacters; splitting here is intentional.
    local bytes=()
    read -r -a bytes <<< "$(printf '%s' "$header" | tr '\n' ' ')"
    [ "${#bytes[@]}" -ge 4 ] || return 1
    magic="${bytes[0]}${bytes[1]}${bytes[2]}${bytes[3]}"
    if [ "${2:-elf}" = macho ]; then
        [[ "$magic" = cffaedfe || "$magic" = cefaedfe || "$magic" = cafebabe ]]
    else
        [ "$magic" = 7f454c46 ] && [ "${#bytes[@]}" -ge 20 ] || return 1
        if [ "${bytes[5]}" = 01 ]; then type="${bytes[17]}${bytes[16]}"; else type="${bytes[16]}${bytes[17]}"; fi
        [[ "$type" = 0002 || "$type" = 0003 ]]
    fi
}

runtime_system_library() {
    if [ "${2:-elf}" = macho ]; then
        [[ "$1" = /usr/lib/* || "$1" = /System/Library/* ]]
    else
        [[ "$1" =~ ^(ld-linux[^/]*|ld64)\.so(\.[0-9]+)*$ ||
           "$1" =~ ^(ld-musl-[^/]+|libc\.musl-[^/]+)\.so\.1$ ||
           "$1" =~ ^lib(c|m|dl|pthread|rt|resolv|util|anl)\.so\.[0-9]+$ ]]
    fi
}

runtime_copy_stdlib() {
    mkdir -p "$2"
    # tar preserves symlinks and modes, while excluding development/test files
    # at every level. Both BSD tar and GNU tar support these exclusions.
    tar -C "$1" --exclude=site-packages --exclude=dist-packages \
        --exclude=__pycache__ --exclude=test --exclude=tests --exclude='config-*' -cf - . |
        tar -C "$2" -xf -
}
