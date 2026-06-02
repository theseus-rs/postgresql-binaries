#!/usr/bin/env bash

set -euo pipefail

postgresql_version=$(echo "$1" | awk -F. '{print ""$1"."$2}')
port=65432
test_directory="$(pwd)"
data_directory="$(mktemp -d)"
echo "data_directory=$data_directory"
mkdir -p "$data_directory"

cd "$test_directory/bin"

resolve_binary() {
  local name="$1"

  if [ -x "./$name" ]; then
    printf './%s' "$name"
  elif [ -x "./$name.exe" ]; then
    printf './%s.exe' "$name"
  else
    echo "Unable to find executable: $name" >&2
    exit 1
  fi
}

initdb="$(resolve_binary initdb)"
pg_ctl="$(resolve_binary pg_ctl)"
psql="$(resolve_binary psql)"

"$initdb" -A trust -U postgres -D "$data_directory" -E UTF8
"$pg_ctl" -w -D "$data_directory" -o "-p $port -F" start

cleanup() {
  "$pg_ctl" -w -D "$data_directory" stop &>/dev/null || true
}
trap cleanup EXIT

echo "Running tests..."
set -x

test "$("$psql" -qtAX -h localhost -p "$port" -U postgres -d postgres -c 'SHOW SERVER_VERSION')" = "$postgresql_version"
test "$("$psql" -qtAX -h localhost -p "$port" -U postgres -d postgres -c 'SHOW SERVER_ENCODING')" = "UTF8"
test "$("$psql" -tA -h localhost -p "$port" -U postgres -d postgres -c "SELECT extname FROM pg_extension WHERE extname = 'plpgsql'")" = "plpgsql"

set +x
echo "tests completed successfully"
