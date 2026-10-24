#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <version> <target> <platform>" >&2
  exit 1
fi

VERSION="$1"
TARGET="$2"
ROOT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIRECTORY="${INSTALL_DIRECTORY:-$ROOT_DIRECTORY/postgresql-$VERSION-$TARGET}"

cd "$ROOT_DIRECTORY"
export BUILD_REVISION="${BUILD_REVISION:-$(git rev-parse HEAD)}"

PLATFORM="$3"

case "$TARGET" in
  aarch64-unknown-linux-gnu|x86_64-unknown-linux-gnu|aarch64-unknown-linux-musl|x86_64-unknown-linux-musl) ;;
  *) echo "Unsupported Linux target: $TARGET" >&2; exit 1 ;;
esac
python3 "$ROOT_DIRECTORY/scripts/build-matrix.py" --version "$VERSION" --target "$TARGET" >/dev/null

# Install emulators for builds targeting another CPU architecture.
bash "$ROOT_DIRECTORY/scripts/setup-binfmt.sh"

if [[ "$TARGET" == *musl* ]]; then
  DOCKERFILE="dockerfiles/Dockerfile.linux-musl"
else
  DOCKERFILE="dockerfiles/Dockerfile.linux-gnu"
fi

docker buildx build --file "$DOCKERFILE" --load \
  --build-arg "POSTGRESQL_VERSION=$VERSION" --build-arg "TARGET_CFLAGS=${TARGET_CFLAGS:--O2}" --platform "$PLATFORM" \
  --build-arg "TARGET=$TARGET" --build-arg "BUILD_REVISION=$BUILD_REVISION" \
  --tag postgresql-build:latest .

container_id="$(docker create --platform "$PLATFORM" postgresql-build:latest)"
trap 'docker rm -f "$container_id" >/dev/null' EXIT
mkdir -p "$INSTALL_DIRECTORY"
docker cp "$container_id:/opt/postgresql/." "$INSTALL_DIRECTORY"
