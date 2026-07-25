#!/usr/bin/env bash
# Runs inside a stock CloudNativePG PostgreSQL image, with the extension tree
# mounted at /extensions/timescaledb, optionally the toolkit tree at
# /extensions/timescaledb_toolkit, and this directory at /hack.
set -euo pipefail

ext=/extensions/timescaledb
toolkit=/extensions/timescaledb_toolkit
export PGDATA=/tmp/pgdata

have_toolkit=""
if [ -d "${toolkit}" ]; then
    have_toolkit=1
fi

require() {
    if [ ! -r "$1" ]; then
        echo "not readable as uid $(id -u): $1" >&2
        ls -ld "$(dirname "$1")" >&2 || true
        exit 1
    fi
}

require "${ext}/share/extension/timescaledb.control"
require "${ext}/lib/timescaledb.so"

echo "extension tree: $(find "${ext}/lib" -name '*.so' | wc -l) libraries," \
     "$(find "${ext}/share/extension" -name '*.sql' | wc -l) SQL scripts"

if [ -n "${have_toolkit}" ]; then
    require "${toolkit}/share/extension/timescaledb_toolkit.control"
    echo "toolkit tree:   $(find "${toolkit}/lib" -name '*.so' | wc -l) libraries," \
         "$(find "${toolkit}/share/extension" -name '*.sql' | wc -l) SQL scripts"
fi

if compgen -G "/usr/lib/postgresql/*/lib/timescaledb*" > /dev/null; then
    echo "base image already ships timescaledb, so this test would prove nothing" >&2
    exit 1
fi

# A mismatch here otherwise surfaces later as "cannot open shared object file"
# on a file that plainly exists.
so_arch="$(od -An -t x2 -j 18 -N 2 "${ext}/lib/timescaledb.so" | tr -d ' ')"
case "$(uname -m)" in
    x86_64) want=003e ;;
    aarch64) want=00b7 ;;
    *) want="" ;;
esac
if [ -n "${want}" ] && [ "${so_arch}" != "${want}" ]; then
    echo "extension tree is not built for $(uname -m):" \
         "timescaledb.so has ELF e_machine 0x${so_arch}, expected 0x${want}" >&2
    exit 1
fi

initdb -D "${PGDATA}" --locale=C.UTF-8 --encoding=UTF8 > /dev/null

# extension_control_path and dynamic_library_path are what CloudNativePG sets
# for a mounted extension image. $system and $libdir must reach PostgreSQL
# literally, hence the escaping.
control_path="\$system:${ext}/share"
library_path="\$libdir:${ext}/lib"
if [ -n "${have_toolkit}" ]; then
    control_path="${control_path}:${toolkit}/share"
    library_path="${library_path}:${toolkit}/lib"
fi

cat >> "${PGDATA}/postgresql.conf" <<CONF
extension_control_path = '${control_path}'
dynamic_library_path = '${library_path}'
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

echo
echo "verified TimescaleDB ${installed}, license=${license}, continuous aggregate rows=${cagg_rows}"

if [ -n "${have_toolkit}" ]; then
    psql -h /tmp -d postgres -v ON_ERROR_STOP=1 -f /hack/verify-toolkit.sql
    toolkit_version="$(q "SELECT extversion FROM pg_extension WHERE extname = 'timescaledb_toolkit'")"
    toolkit_advertised="$(q "SELECT default_version FROM pg_available_extensions WHERE name = 'timescaledb_toolkit'")"
    if [ "${toolkit_version}" != "${toolkit_advertised}" ]; then
        echo "toolkit installed ${toolkit_version}, control file advertises ${toolkit_advertised}" >&2
        exit 1
    fi
    echo "verified TimescaleDB Toolkit ${toolkit_version}"
fi

pg_ctl -D "${PGDATA}" -w stop > /dev/null
