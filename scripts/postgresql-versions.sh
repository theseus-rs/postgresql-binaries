#!/bin/sh

# The supported major releases, current packaging versions and EOL dates.
# Keep versions in ascending order and update the eol command when adding majors.
# CI, source validation, release verification and upstream checks share this
# policy; the runtime test also uses it without Python or jq.
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
    eol)
        validate "${2:?Missing version}"
        case "${2%%.*}" in
            14) echo 2026-11-12 ;;
            15) echo 2027-11-11 ;;
            16) echo 2028-11-09 ;;
            17) echo 2029-11-08 ;;
            18) echo 2030-11-14 ;;
            *) echo "Missing EOL date for PostgreSQL $2" >&2; exit 1 ;;
        esac
        ;;
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
        # These upstream releases fixed strchrnul detection for macOS 15.4
        # SDKs when targeting macOS 15.0. Backport the fix to older sources.
        case "${2%%.*}" in
            14) first_fixed_minor=18 ;;
            15) first_fixed_minor=13 ;;
            16) first_fixed_minor=9 ;;
            17) first_fixed_minor=5 ;;
            *) first_fixed_minor=0 ;;
        esac
        upstream_version=${2%.*}
        if [ "${upstream_version#*.}" -lt "$first_fixed_minor" ]; then
            printf 'postgresql-%s-macos-strchrnul.patch\n' "${2%%.*}"
        fi
        ;;
    *)
        echo "Usage: $0 <current|latest|oldest|validate VERSION|eol VERSION|supports-target VERSION TARGET|baseline-llvm VERSION|source-patches VERSION>" >&2
        exit 1
        ;;
esac
