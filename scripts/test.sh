#!/usr/bin/env bash

set -euo pipefail

[[ "${1:-}" =~ ^(14|15|16|17|18)\.[0-9]+\.[0-9]+$ ]]

postgresql_version=$(echo "$1" | awk -F. '{print ""$1"."$2}')
version_num=$(awk -F. '{printf "%d%04d", $1, $2}' <<< "$1")
port=${PGTEST_PORT:-65432}
test_directory="$(pwd)"
data_directory="$(mktemp -d)"
echo "data_directory=$data_directory"
mkdir -p "$data_directory"

cd "$test_directory/bin"
test "$(./postgres --version)" = "postgres (PostgreSQL) $postgresql_version"
./initdb -A trust -U postgres -D "$data_directory" -E UTF8
cleanup() {
    ./pg_ctl -w -D "$data_directory" stop >/dev/null 2>&1 || true
    rm -rf "$data_directory"
}
trap cleanup EXIT
./pg_ctl -w -D "$data_directory" -l "$data_directory/server.log" -o "-p $port -F -h 127.0.0.1" start

# The relocated install must carry its own tzdata.
test -f ../share/timezone/UTC || test -f ../share/postgresql/timezone/UTC
query() {
    ./psql -X -v ON_ERROR_STOP=1 -qtAX -h localhost -p "$port" -U postgres -d postgres -c "$1"
}
query "SET TIME ZONE 'UTC'"
query "SET TIME ZONE 'America/New_York'"
test "$(query "SELECT extract(hour FROM timestamp '2026-01-15 12:00' AT TIME ZONE 'UTC' AT TIME ZONE 'America/New_York')")" = 7
test "$(query "SELECT extract(hour FROM timestamp '2026-07-15 12:00' AT TIME ZONE 'UTC' AT TIME ZONE 'America/New_York')")" = 8

echo "Running tests..."
set -x

test "$(./psql -qtAX -h localhost -p $port -U postgres -d postgres -c 'SHOW SERVER_VERSION')" = "$postgresql_version"
test "$(./psql -qtAX -h localhost -p "$port" -U postgres -d postgres -c 'SHOW server_version_num')" = "$version_num"
test "$(./psql -qtAX -h localhost -p $port -U postgres -d postgres -c 'SHOW SERVER_ENCODING')" = "UTF8"
test $(./psql -tA -h localhost -p $port -U postgres -d postgres -c "SELECT extname FROM pg_extension WHERE extname = 'plpgsql'") = "plpgsql"

set +x
echo "tests completed successfully"
