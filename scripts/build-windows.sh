#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <version> <target> <vcpkg-triplet>" >&2
  exit 1
fi

VERSION="$1"
TARGET="$2"
ROOT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POSTGRESQL_VERSION="${VERSION%.*}"
POSTGRESQL_MAJOR_VERSION="${VERSION%%.*}"
INSTALL_DIRECTORY="${INSTALL_DIRECTORY:-$ROOT_DIRECTORY/postgresql-$VERSION-$TARGET}"

cd "$ROOT_DIRECTORY"

VCPKG_TRIPLET="$3"

if [[ "$TARGET" == "aarch64-pc-windows-msvc" && "$POSTGRESQL_MAJOR_VERSION" -lt 16 ]]; then
  echo "Windows ARM64 source builds require PostgreSQL 16 or newer." >&2
  exit 1
fi

# Run from Git Bash with the Visual Studio developer environment inherited.
: "${VCToolsInstallDir:?Run from a Visual Studio developer command prompt}"
: "${VSCMD_ARG_HOST_ARCH:?The MSVC host architecture must be configured}"
: "${VSCMD_ARG_TGT_ARCH:?The MSVC target architecture must be configured}"

runner_temp="$(cygpath -u "${RUNNER_TEMP:-${TMPDIR:-/tmp}}")"
source_archive="$runner_temp/postgresql-$POSTGRESQL_VERSION.tar.gz"
SOURCE_DIRECTORY="$runner_temp/postgresql-$POSTGRESQL_VERSION"

curl -fsSL "https://ftp.postgresql.org/pub/source/v$POSTGRESQL_VERSION/postgresql-$POSTGRESQL_VERSION.tar.gz" -o "$source_archive"
tar xzf "$source_archive" -C "$runner_temp"
python "$ROOT_DIRECTORY/scripts/patch-postgresql-libxml2.py" "$SOURCE_DIRECTORY"

if [[ "$TARGET" == "aarch64-pc-windows-msvc" ]]; then
  python "$ROOT_DIRECTORY/scripts/patch-postgresql-windows-arm64.py" "$SOURCE_DIRECTORY"
fi

python -m pip install --upgrade pip
python -m pip install meson ninja
choco install winflexbison3 --yes --no-progress

export PATH="/c/ProgramData/chocolatey/bin:$PATH"
hash -r
win_flex --version
win_bison --version

vcpkg_root="${VCPKG_INSTALLATION_ROOT:-}"

if [ -n "$vcpkg_root" ]; then
  vcpkg_root="$(cygpath -u "$vcpkg_root")"
elif [ -d /c/vcpkg ]; then
  vcpkg_root="/c/vcpkg"
else
  vcpkg_root="$runner_temp/vcpkg"
fi

if [ ! -f "$vcpkg_root/vcpkg.exe" ]; then
  git clone --depth 1 https://github.com/microsoft/vcpkg "$vcpkg_root"
  cmd //c "$(cygpath -w "$vcpkg_root")\\bootstrap-vcpkg.bat -disableMetrics"
fi

vcpkg_exe="$vcpkg_root/vcpkg.exe"
export VCPKG_ROOT="$vcpkg_root"
openssl_package="openssl"
if [ "$POSTGRESQL_MAJOR_VERSION" -lt 16 ]; then
  # Solution.pm invokes openssl.exe to detect the library version.
  openssl_package="openssl[tools]"
fi

"$vcpkg_exe" install \
  --triplet "$VCPKG_TRIPLET" \
  --clean-after-build \
  icu \
  libxml2 \
  libxslt \
  lz4 \
  "$openssl_package" \
  pkgconf \
  zlib \
  zstd

vcpkg_installed="$vcpkg_root/installed/$VCPKG_TRIPLET"

export CMAKE_PREFIX_PATH="$(cygpath -m "$vcpkg_installed")"
export PKG_CONFIG_PATH="$(cygpath -m "$vcpkg_installed/lib/pkgconfig");$(cygpath -m "$vcpkg_installed/share/pkgconfig")"
export VCPKG_INSTALLED="$vcpkg_installed"

vctools_bin="$(cygpath -u "$VCToolsInstallDir")/bin/Host${VSCMD_ARG_HOST_ARCH}/${VSCMD_ARG_TGT_ARCH}"
export PATH="$vctools_bin:$VCPKG_INSTALLED/bin:$PATH"
export MSYS2_ARG_CONV_EXCL="/nologo;/symbols;/out:"
hash -r

link_path="$(command -v link)"
echo "Using cl: $(command -v cl)"
echo "Using link: $link_path"

if [[ "$link_path" == "/usr/bin/link" || "$link_path" == *"/Git/usr/bin/link"* ]]; then
  echo "ERROR: MSVC link.exe is not first on PATH"
  exit 1
fi

if [ "$POSTGRESQL_MAJOR_VERSION" -ge 16 ]; then
  # Select vcpkg's native executable explicitly; Strawberry's pkg-config.bat
  # can be found first on PATH but does not work on Windows ARM64.
  export PKG_CONFIG="$(cygpath -m "$vcpkg_installed/tools/pkgconf/pkgconf.exe")"
  "$PKG_CONFIG" --version
  "$PKG_CONFIG" --print-errors --exists icu-uc icu-i18n

  build_directory="$runner_temp/postgresql-build"
  python_path="$(cygpath -m "$(command -v python)")"

  meson setup "$build_directory" "$SOURCE_DIRECTORY" \
    --prefix "$(cygpath -m "$INSTALL_DIRECTORY")" \
    --buildtype release \
    -Dauto_features=disabled \
    -Ddocs=disabled \
    -Ddocs_pdf=disabled \
    -Dextra_include_dirs="$(cygpath -m "$VCPKG_INSTALLED/include")" \
    -Dextra_lib_dirs="$(cygpath -m "$VCPKG_INSTALLED/lib")" \
    -Dgssapi=disabled \
    -Dicu=enabled \
    -Dldap=disabled \
    -Dlibxml=enabled \
    -Dlibxslt=enabled \
    -Dllvm=disabled \
    -Dlz4=enabled \
    -Dnls=disabled \
    -Dpgport=5432 \
    -Dplperl=disabled \
    -Dplpython=enabled \
    -Dpltcl=disabled \
    -DPYTHON="$python_path" \
    -Dreadline=disabled \
    -Dssl=openssl \
    -Duuid=none \
    -Dzlib=enabled \
    -Dzstd=enabled
  meson compile -C "$build_directory"
  meson install -C "$build_directory"
else
  # PostgreSQL 14/15's Solution.pm expects the layout of standalone Windows
  # dependency installers. Stage it separately from the vcpkg installation.
  legacy_dependencies="$(mktemp -d "$runner_temp/postgresql-msvc-deps.XXXXXX")"
  cp -R "$VCPKG_INSTALLED/include" "$VCPKG_INSTALLED/lib" "$VCPKG_INSTALLED/bin" "$legacy_dependencies/"
  cp "$VCPKG_INSTALLED/tools/openssl/openssl.exe" "$legacy_dependencies/bin/openssl.exe"

  # vcpkg used zlib.lib before zlib 1.3.2 switched to z.lib.
  if [ -f "$VCPKG_INSTALLED/lib/zlib.lib" ]; then
    cp "$VCPKG_INSTALLED/lib/zlib.lib" "$legacy_dependencies/lib/zdll.lib"
  else
    cp "$VCPKG_INSTALLED/lib/z.lib" "$legacy_dependencies/lib/zdll.lib"
  fi
  cp "$VCPKG_INSTALLED/lib/lz4.lib" "$legacy_dependencies/lib/liblz4.lib"
  mkdir -p "$legacy_dependencies/lib64"
  cp "$VCPKG_INSTALLED/lib/"{icuin,icuuc,icudt}.lib "$legacy_dependencies/lib64/"

  vcpkg_prefix="$(cygpath -m "$legacy_dependencies")"
  python_root="$(python - <<'PY'
import sys
sys.stdout.write(sys.base_prefix)
PY
  )"
  python_root="$(cygpath -m "$python_root")"
  config_path="$SOURCE_DIRECTORY/src/tools/msvc/config.pl"
  buildenv_path="$SOURCE_DIRECTORY/src/tools/msvc/buildenv.pl"

  {
    echo 'use strict;'
    echo 'use warnings;'
    echo 'our $config = {'
    echo '  asserts => 0,'
    echo '  ldap => 0,'
    echo "  icu => '$vcpkg_prefix',"
    echo "  lz4 => '$vcpkg_prefix',"
    echo "  openssl => '$vcpkg_prefix',"
    if [ "$POSTGRESQL_MAJOR_VERSION" -ge 15 ]; then
      echo "  python => '$python_root',"
    fi
    echo "  xml => '$vcpkg_prefix',"
    echo "  xslt => '$vcpkg_prefix',"
    echo "  zlib => '$vcpkg_prefix',"
    echo '};'
    echo '1;'
  } > "$config_path"

  {
    echo '$ENV{MSBFLAGS}="/m";'
    echo '1;'
  } > "$buildenv_path"

  export PATH="/c/Strawberry/perl/bin:$PATH"
  cd "$SOURCE_DIRECTORY/src/tools/msvc"
  perl build.pl
  perl install.pl "$(cygpath -m "$INSTALL_DIRECTORY")"
fi

cp "$SOURCE_DIRECTORY/COPYRIGHT" "$INSTALL_DIRECTORY"

if [ -d "$VCPKG_INSTALLED/bin" ]; then
  find "$VCPKG_INSTALLED/bin" -maxdepth 1 -type f -name '*.dll' -exec cp {} "$INSTALL_DIRECTORY/bin/" \;
fi

python_root="$(python - <<'PY'
import sys
sys.stdout.write(sys.base_prefix)
PY
)"
python_root="$(cygpath -u "$python_root")"
find "$python_root" -maxdepth 1 -type f -iname 'python*.dll' -exec cp {} "$INSTALL_DIRECTORY/bin/" \; || true
