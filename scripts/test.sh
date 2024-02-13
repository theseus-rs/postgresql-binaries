#!/usr/bin/env bash

set -e

postgresql_version=$(echo "$1" | awk -F. '{print ""$1"."$2}')
port=65432
test_directory="$(pwd)"
data_directory="$(mktemp -d)"
echo "data_directory=$data_directory"
mkdir -p "$data_directory"

cd "$test_directory/bin"
./initdb -A trust -U postgres -D "$data_directory" -E UTF8
./pg_ctl -w -D "$data_directory" -o "-p $port -F" start

trap "./pg_ctl -w -D $data_directory stop &>/dev/null" EXIT

echo "Running tests..."
set -x

test "$(./psql -qtAX -h localhost -p $port -U postgres -d postgres -c 'SHOW SERVER_VERSION')" = "$postgresql_version"
test "$(./psql -qtAX -h localhost -p $port -U postgres -d postgres -c 'SHOW SERVER_ENCODING')" = "UTF8"
test $(./psql -tA -h localhost -p $port -U postgres -d postgres -c "SELECT extname FROM pg_extension WHERE extname = 'plpgsql'") = "plpgsql"

set +x
echo "tests completed successfully"
