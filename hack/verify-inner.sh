#!/usr/bin/env bash
# Runs inside a stock CloudNativePG PostgreSQL image, with the extension tree
# mounted at /extensions/timescaledb and this directory at /hack.
set -euo pipefail

ext=/extensions/timescaledb
export PGDATA=/tmp/pgdata

test -f "${ext}/share/extension/timescaledb.control"
test -f "${ext}/lib/timescaledb.so"

if compgen -G "/usr/lib/postgresql/*/lib/timescaledb*" > /dev/null; then
    echo "base image already ships timescaledb, so this test would prove nothing" >&2
    exit 1
fi

initdb -D "${PGDATA}" --locale=C.UTF-8 --encoding=UTF8 > /dev/null

# extension_control_path and dynamic_library_path are what CloudNativePG sets
# for a mounted extension image. $system and $libdir must reach PostgreSQL
# literally, hence the escaping.
cat >> "${PGDATA}/postgresql.conf" <<CONF
extension_control_path = '\$system:${ext}/share'
dynamic_library_path = '\$libdir:${ext}/lib'
shared_preload_libraries = 'timescaledb'
timescaledb.license = 'timescale'
CONF

pg_ctl -D "${PGDATA}" -l /tmp/postgres.log -o "-k /tmp -c listen_addresses=" -w start

q() { psql -h /tmp -d postgres -qtAX -c "$1"; }

advertised="$(q "SELECT default_version FROM pg_available_extensions WHERE name = 'timescaledb'")"
if [ "${advertised}" != "${TSDB_VERSION}" ]; then
    echo "control file advertises ${advertised}, expected ${TSDB_VERSION}" >&2
    exit 1
fi

psql -h /tmp -d postgres -v ON_ERROR_STOP=1 -f /hack/verify.sql

installed="$(q "SELECT extversion FROM pg_extension WHERE extname = 'timescaledb'")"
license="$(q "SHOW timescaledb.license")"
cagg_rows="$(q "SELECT count(*) FROM metrics_1m")"

if [ "${installed}" != "${TSDB_VERSION}" ]; then
    echo "installed ${installed}, expected ${TSDB_VERSION}" >&2
    exit 1
fi
if [ "${license}" != "timescale" ]; then
    echo "license is ${license}, expected timescale (Community edition)" >&2
    exit 1
fi
if [ "${cagg_rows}" -eq 0 ]; then
    echo "continuous aggregate produced no rows" >&2
    exit 1
fi

pg_ctl -D "${PGDATA}" -w stop > /dev/null

echo
echo "verified TimescaleDB ${installed}, license=${license}, continuous aggregate rows=${cagg_rows}"
