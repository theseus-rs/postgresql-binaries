#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <version> <target>" >&2
  exit 1
fi

VERSION="$1"
TARGET="$2"
ROOT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POSTGRESQL_VERSION="${VERSION%.*}"
INSTALL_DIRECTORY="${INSTALL_DIRECTORY:-$ROOT_DIRECTORY/postgresql-$VERSION-$TARGET}"

cd "$ROOT_DIRECTORY"

SOURCE_DIRECTORY="$ROOT_DIRECTORY/postgresql-src"
branch=$(echo "$VERSION" | awk -F. '{print "REL_"$1"_"$2}')
git clone --depth 1 --branch "$branch" -c advice.detachedHead=false https://git.postgresql.org/git/postgresql.git "$SOURCE_DIRECTORY"
python3 "$ROOT_DIRECTORY/scripts/patch-postgresql-libxml2.py" "$SOURCE_DIRECTORY"

brew install \
  fop \
  icu4c \
  libxml2 \
  libxslt \
  lld \
  llvm \
  lz4 \
  openssl@3 \
  readline \
  zstd

brew_dir="/usr/local"
if [ "$TARGET" == "aarch64-apple-darwin" ]; then
  brew_dir="/opt/homebrew"
fi
brew_opt_dir="$brew_dir/opt"
ls -l "$brew_opt_dir"

brew_prefix() {
  local formula="$1"
  local fallback="$2"

  brew --prefix "$formula" 2>/dev/null || printf '%s\n' "$fallback"
}

icu_prefix="$(brew_prefix icu4c "${brew_opt_dir}/icu4c")"
openssl_prefix="$(brew_prefix openssl@3 "${brew_opt_dir}/openssl")"
libxml2_prefix="$(brew_prefix libxml2 "${brew_opt_dir}/libxml2")"
libxslt_prefix="$(brew_prefix libxslt "${brew_opt_dir}/libxslt")"
llvm_prefix="$(brew_prefix llvm "${brew_opt_dir}/llvm")"
lz4_prefix="$(brew_prefix lz4 "${brew_opt_dir}/lz4")"
readline_prefix="$(brew_prefix readline "${brew_opt_dir}/readline")"
zstd_prefix="$(brew_prefix zstd "${brew_opt_dir}/zstd")"

include_flags=(
  "-I${icu_prefix}/include"
  "-I${openssl_prefix}/include"
  "-I${libxml2_prefix}/include"
  "-I${libxslt_prefix}/include"
  "-I${lz4_prefix}/include"
  "-I${readline_prefix}/include"
  "-I${zstd_prefix}/include"
)
library_flags=(
  "-L${icu_prefix}/lib"
  "-L${openssl_prefix}/lib"
  "-L${libxml2_prefix}/lib"
  "-L${libxslt_prefix}/lib"
  "-L${lz4_prefix}/lib"
  "-L${readline_prefix}/lib"
  "-L${zstd_prefix}/lib"
)
pkg_config_paths=(
  "${icu_prefix}/lib/pkgconfig"
  "${openssl_prefix}/lib/pkgconfig"
  "${libxml2_prefix}/lib/pkgconfig"
  "${libxslt_prefix}/lib/pkgconfig"
  "${lz4_prefix}/lib/pkgconfig"
  "${readline_prefix}/lib/pkgconfig"
  "${zstd_prefix}/lib/pkgconfig"
)

export CPPFLAGS="${include_flags[*]}"
export LDFLAGS="${library_flags[*]}"
export LLVM_CONFIG="${llvm_prefix}/bin/llvm-config"
export PKG_CONFIG_PATH="$(IFS=:; echo "${pkg_config_paths[*]}")${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

cd "$SOURCE_DIRECTORY"
major_version=$(echo "$POSTGRESQL_VERSION" | awk -F. '{print $1}')

./configure \
  --prefix "$INSTALL_DIRECTORY" \
  --enable-integer-datetimes \
  --enable-option-checking=fatal \
  $([ $major_version -le 16 ] && echo "--enable-thread-safety") \
  $([ $major_version -ge 14 ] && echo "--with-icu" || echo "--without-icu") \
  --without-ldap \
  --with-libxml \
  --with-libxslt \
  $([ $major_version -ge 16 ] && echo "--with-llvm") \
  $([ $major_version -ge 14 ] && echo "--with-lz4") \
  --with-openssl \
  --with-pgport=5432 \
  $([ $major_version -ge 15 ] && echo "--with-python") \
  --with-readline \
  --with-system-tzdata=/usr/share/zoneinfo \
  --with-uuid=e2fs \
  $([ $major_version -ge 16 ] && echo "--with-zstd")
make $([ $major_version -ge 15 ] && echo "world-bin")
make $([ $major_version -ge 15 ] && echo "install-world-bin" || echo "install")
make -C contrib install

cp "$SOURCE_DIRECTORY/COPYRIGHT" "$INSTALL_DIRECTORY"
cd "$ROOT_DIRECTORY"

# Make the installation relocatable and bundle its Homebrew dependencies.
"$ROOT_DIRECTORY/scripts/macos-bundle-deps.sh" "$INSTALL_DIRECTORY" "$brew_dir"
