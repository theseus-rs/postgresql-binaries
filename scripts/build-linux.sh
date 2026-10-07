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

PLATFORM="$3"

# Install emulators for builds targeting another CPU architecture.
# tonistiigi/binfmt:latest, resolved 2026-09-27
docker run --privileged --rm tonistiigi/binfmt --install all

if [[ "$TARGET" == *musl* ]]; then
  DOCKERFILE="dockerfiles/Dockerfile.linux-musl"
else
  DOCKERFILE="dockerfiles/Dockerfile.linux-gnu"
fi

docker buildx build --file "$DOCKERFILE" --load \
  --build-arg "POSTGRESQL_VERSION=$VERSION" --platform "$PLATFORM" \
  --tag postgresql-build:latest .

container_id="$(docker create --platform "$PLATFORM" postgresql-build:latest)"
trap 'docker rm -f "$container_id" >/dev/null' EXIT
mkdir -p "$INSTALL_DIRECTORY"
docker cp "$container_id:/opt/postgresql/." "$INSTALL_DIRECTORY"
