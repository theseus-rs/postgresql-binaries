#!/usr/bin/env bash

set -eu

printf '%s\n' "${1:-}" | grep -Eq '^(14|15|16|17|18)\.[0-9]+\.[0-9]+$'

postgresql_version=$(echo "$1" | awk -F. '{print ""$1"."$2}')
version_num=$(printf '%s\n' "$1" | awk -F. '{printf "%d%04d", $1, $2}')
port=${PGTEST_PORT:-65432}
test_directory="$(pwd)"
data_directory="$(mktemp -d)"
echo "data_directory=$data_directory"
mkdir -p "$data_directory"

cd "$test_directory/bin"
test "$(./postgres --version)" = "postgres (PostgreSQL) $postgresql_version"
./initdb -A trust -U postgres -D "$data_directory" -E UTF8
cleanup() {
    status=$?
    if [ "$status" -ne 0 ] && [ -f "$data_directory/server.log" ]; then
        cat "$data_directory/server.log" >&2
    fi
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

# Exercise libraries loaded only by extensions, not just postgres itself.
query "CREATE EXTENSION pgcrypto; SELECT encode(digest('portable', 'sha256'), 'hex')"
query "CREATE EXTENSION xml2; SELECT xml_is_well_formed('<portable/>')"
query "CREATE EXTENSION hstore; SELECT 'a=>b'::hstore -> 'a'"
query "CREATE TABLE portable_lz4(value text COMPRESSION lz4)"
query "INSERT INTO portable_lz4 VALUES (repeat('portable-value-', 2000))"
test "$(query 'SELECT pg_column_compression(value) FROM portable_lz4')" = lz4
./pg_dump -h localhost -p "$port" -U postgres -d postgres -Fc -Z 1 -f "$data_directory/gzip.dump"
./pg_restore -f "$data_directory/gzip.sql" "$data_directory/gzip.dump"
if ./pg_config --configure | grep -q -- '--with-zstd'; then
    ./pg_dump -h localhost -p "$port" -U postgres -d postgres -Fc --compress=zstd:1 -f "$data_directory/zstd.dump"
    ./pg_restore -f "$data_directory/zstd.sql" "$data_directory/zstd.dump"
fi
if find ../lib -name 'plpython3.*' | grep -q .; then
    query "CREATE EXTENSION plpython3u"
    query 'CREATE FUNCTION portable_python() RETURNS text LANGUAGE plpython3u AS $$
import ssl, json, zlib, decimal
return json.dumps({"value": str(decimal.Decimal("1.25"))})
$$'
    test "$(query 'SELECT portable_python()')" = '{"value": "1.25"}'
fi
if find ../lib -name 'llvmjit.*' | grep -q .; then
    test "$(query 'SELECT pg_jit_available()')" = t
    query 'SET jit = on; SET jit_above_cost = 0; SELECT sum(i) FROM generate_series(1, 100) i'
fi

echo "Running tests..."
set -x

test "$(./psql -qtAX -h localhost -p "$port" -U postgres -d postgres -c 'SHOW SERVER_VERSION')" = "$postgresql_version"
test "$(./psql -qtAX -h localhost -p "$port" -U postgres -d postgres -c 'SHOW server_version_num')" = "$version_num"
test "$(./psql -qtAX -h localhost -p "$port" -U postgres -d postgres -c 'SHOW SERVER_ENCODING')" = "UTF8"
test "$(query "SELECT extname FROM pg_extension WHERE extname = 'plpgsql'")" = plpgsql

set +x
echo "tests completed successfully"
