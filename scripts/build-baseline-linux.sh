#!/usr/bin/env bash

# Build libc and every dependency for targets below the distro CPU/ABI floor.
set -euo pipefail
version=${1:?Usage: build-baseline-linux.sh <version> <target> <platform> [runtime]}
target=${2:?Missing target}
platform=${3:?Missing platform}
mode=${4:-build}
[[ "$mode" = build || "$mode" = runtime ]]
case "$target" in
    i586-unknown-linux-gnu|i586-unknown-linux-musl|arm-unknown-linux-gnueabihf|arm-unknown-linux-musleabi) ;;
    *) echo "Unsupported source-built baseline: $target" >&2; exit 1 ;;
esac
root=$(cd "$(dirname "$0")/.." && pwd)
sh "$root/scripts/postgresql-versions.sh" validate "$version"
llvm_version=$(sh "$root/scripts/postgresql-versions.sh" baseline-llvm "$version")
cache=${BUILDROOT_CACHE:-${RUNNER_TEMP:-${XDG_CACHE_HOME:-$HOME/.cache}}/postgresql-buildroot}
mkdir -p "$cache"
cache=$(cd "$cache" && pwd)
buildroot_version=2026.08
buildroot_sha256=87aaca4164ea9d5c8085854953018263f7963f07c22e73a2a2185cc98c581c34
glibc_version=2.36-254-g872743b638cb48a015bb32d0cb229938ed243ff7
archive="$cache/buildroot-$buildroot_version.tar.xz"
if [ ! -f "$archive" ]; then
    curl --fail --location --silent --show-error --retry 3 \
        "https://buildroot.org/downloads/buildroot-$buildroot_version.tar.xz" -o "$archive.download"
    printf '%s  %s\n' "$buildroot_sha256" "$archive.download" | sha256sum -c -
    mv "$archive.download" "$archive"
fi
printf '%s  %s\n' "$buildroot_sha256" "$archive" | sha256sum -c -
buildroot="$cache/buildroot-$buildroot_version"
if [ ! -d "$buildroot" ]; then tar xJf "$archive" -C "$cache"; fi
output="$cache/$target"
if [ "$mode" = runtime ]; then output="$cache/runtime-$target"; fi
if [[ "$target" != *musl* ]]; then
    output="$output-glibc-2.36"
elif [ "$mode" = build ] && [ -n "$llvm_version" ]; then
    # Never reuse a sysroot or host compiler built for another LLVM ABI.
    output="$output-llvm-$llvm_version"
fi
mkdir -p "$output"
source_directory="$output/postgresql-source-$version"

cat "$root/buildroot/runtime.config" > "$output/defconfig"
case "$target" in
    i586-*)
        printf '%s\n' BR2_i386=y BR2_x86_i586=y >> "$output/defconfig"
        ;;
    arm-unknown-linux-gnueabihf)
        printf '%s\n' BR2_arm=y BR2_arm1176jzf_s=y BR2_ARM_EABIHF=y BR2_ARM_FPU_VFPV2=y >> "$output/defconfig"
        ;;
    arm-unknown-linux-musleabi)
        printf '%s\n' BR2_arm=y BR2_arm1176jz_s=y BR2_ARM_EABI=y BR2_ARM_SOFT_FLOAT=y >> "$output/defconfig"
        ;;
esac
if [[ "$target" = *musl* ]]; then
    echo BR2_TOOLCHAIN_BUILDROOT_MUSL=y >> "$output/defconfig"
else
    echo BR2_TOOLCHAIN_BUILDROOT_GLIBC=y >> "$output/defconfig"
fi
printf 'BR2_GLOBAL_PATCH_DIR="%s/buildroot/patches"\n' "$root" >> "$output/defconfig"
if [ "$mode" = build ]; then
    cat "$root/buildroot/dependencies.config" >> "$output/defconfig"
    if [[ "$target" = *musl* && -n "$llvm_version" ]]; then
        echo BR2_PACKAGE_LLVM=y >> "$output/defconfig"
    fi
    if [ ! -d "$source_directory" ]; then
        "$root/scripts/fetch-source.sh" "$version" "$source_directory"
    fi
    python3 "$root/scripts/patch-postgresql-libxml2.py" "$source_directory"
    cp "$root/buildroot/cross-python.in" "$source_directory/cross-python"
    chmod +x "$source_directory/cross-python"
fi
jobs=${BUILDROOT_JOBS:-$(getconf _NPROCESSORS_ONLN)}
if [ "$jobs" -gt 6 ]; then jobs=6; fi
printf 'BR2_JLEVEL=%s\nBR2_DL_DIR="%s/dl"\n' "$jobs" "$cache" >> "$output/defconfig"
cflags=$(python3 - "$root/targets.json" "$target" <<'PYTHON'
import json, sys
print(next(t["cflags"] for t in json.load(open(sys.argv[1])) if t["target"] == sys.argv[2]))
PYTHON
)
printf 'BR2_TARGET_OPTIMIZATION="%s"\n' "$cflags" >> "$output/defconfig"
make_arguments=(-C "$buildroot" "O=$output" "BR2_EXTERNAL=$root/buildroot"
    "PG_PACKAGING_VERSION=$version" "PG_MAJOR_VERSION=${version%%.*}" "PG_SOURCE_DIRECTORY=$source_directory")
if [[ "$target" != *musl* ]]; then
    # Preserve the existing Debian 12 libc floor while rebuilding for older CPUs.
    # Use only this version's hashes, including its differing LICENSES file.
    make_arguments+=("GLIBC_VERSION=$glibc_version" "GLIBC_LICENSE_FILES=COPYING COPYING.LIB LICENSES"
        "GLIBC_HASH_FILES=$root/buildroot/patches/glibc/$glibc_version/glibc.hash")
fi
if [[ "$target" = *musl* && "$mode" = build && -n "$llvm_version" ]]; then
    llvm_hash="$root/buildroot/patches/llvm-project/$llvm_version/llvm-project.hash"
    make_arguments+=("LLVM_PROJECT_VERSION_MAJOR=${llvm_version%%.*}" "LLVM_PROJECT_VERSION=$llvm_version"
        "LLVM_HASH_FILES=$llvm_hash" "HOST_LLVM_HASH_FILES=$llvm_hash"
        "CLANG_HASH_FILES=$llvm_hash" "HOST_CLANG_HASH_FILES=$llvm_hash"
        "HOST_LLVM_CMAKE_HASH_FILES=$llvm_hash"
        "LLVM_LICENSE_FILES=llvm/LICENSE.TXT" "CLANG_LICENSE_FILES=clang/LICENSE.TXT")
fi
make "${make_arguments[@]}" "BR2_DEFCONFIG=$output/defconfig" defconfig
make "${make_arguments[@]}"

python3 "$root/scripts/prepare-baseline-runtime.py" "$output/target" "$output/runtime"
runtime_image="postgresql-runtime:$target"
docker build --platform "$platform" --file "$root/dockerfiles/Dockerfile.baseline-runtime" \
    --tag "$runtime_image" "$output/runtime"
if [ -n "${GITHUB_ENV:-}" ]; then echo "RUNTIME_IMAGE=$runtime_image" >> "$GITHUB_ENV"; fi

if [ "$mode" = build ]; then
    make "${make_arguments[@]}" legal-info
    install_directory=${INSTALL_DIRECTORY:-$root/postgresql-$version-$target}
    mkdir -p "$install_directory"
    cp -a "$output/target/opt/postgresql/." "$install_directory/"
    RUNTIME_SYSROOT="$output/target" "$root/scripts/bundle-runtime.sh" "$install_directory"
    python3 "$root/scripts/collect-buildroot-notices.py" "$output" "$install_directory"
    cp "$output/.config" "$install_directory/buildroot.config"
    # Query the target executable under its matching runtime and CPU emulation.
    export PG_CONFIG_COMMAND
    PG_CONFIG_COMMAND=$(python3 - "$platform" "$install_directory" "$runtime_image" <<'PYTHON'
import json, sys
print(json.dumps(["docker", "run", "--rm", "--platform", sys.argv[1],
                  "--mount", f"type=bind,src={sys.argv[2]},dst=/opt/postgresql,readonly",
                  "--entrypoint", "/opt/postgresql/bin/pg_config", sys.argv[3]]))
PYTHON
    )
    compiler=$(find "$output/host/bin" -name '*-gcc' -print -quit)
    test -n "$compiler"
    BUILD_REVISION="${BUILD_REVISION:-$(git -C "$root" rev-parse HEAD)}" CC="$compiler" \
        python3 "$root/scripts/build-metadata.py" "$install_directory" "$version" "$target"
fi
