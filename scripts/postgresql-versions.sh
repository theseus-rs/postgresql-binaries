#!/bin/sh

# The supported major releases and the current packaging version of each.
# Keep this in ascending order. CI, source validation and release verification
# share this policy; the runtime test also uses it without Python or jq.
set -eu
versions='14.24.0 15.19.0 16.15.0 17.11.0 18.6.0'

validate() {
    case "$1" in
        *[!0-9.]*) echo "Malformed PostgreSQL version: $1" >&2; return 1 ;;
    esac
    if printf '%s\n' "$1" | grep -Eq '^[1-9][0-9]*\.[0-9]+\.[0-9]+$'; then
        for supported in $versions; do
            if [ "${1%%.*}" = "${supported%%.*}" ]; then return 0; fi
        done
    fi
    echo "Unsupported or malformed PostgreSQL version: $1" >&2
    return 1
}

case "${1:-}" in
    current) printf '%s\n' $versions ;;
    latest)
        for version in $versions; do :; done
        printf '%s\n' "$version"
        ;;
    oldest)
        for version in $versions; do printf '%s.0.0\n' "${version%%.*}"; done
        ;;
    validate) validate "${2:?Missing version}" ;;
    supports-target)
        validate "${2:?Missing version}"
        # PostgreSQL's Meson Windows ARM64 build starts with PostgreSQL 16.
        if [ "${3:?Missing target}" = aarch64-pc-windows-msvc ] && [ "${2%%.*}" -lt 16 ]; then
            echo false
        else
            echo true
        fi
        ;;
    baseline-llvm)
        validate "${2:?Missing version}"
        # Match Alpine and macOS. PostgreSQL 16.0 also needs the upstream
        # opaque-pointer backport selected by source-patches below.
        if [ "${2%%.*}" -ge 16 ]; then echo 16.0.6; fi
        ;;
    source-patches)
        validate "${2:?Missing version}"
        # LLVM 16 support shipped in PostgreSQL 16.1. Apply its upstream fix
        # to every packaging revision of 16.0, across all build paths.
        if [ "${2%.*}" = 16.0 ]; then echo postgresql-16.0-llvm16.patch; fi
        ;;
    *)
        echo "Usage: $0 <current|latest|oldest|validate VERSION|supports-target VERSION TARGET|baseline-llvm VERSION|source-patches VERSION>" >&2
        exit 1
        ;;
esac
