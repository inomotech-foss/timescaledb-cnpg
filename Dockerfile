# syntax=docker/dockerfile:1

# TimescaleDB packaged as a CloudNativePG extension image.
#
# The final image is FROM scratch and holds nothing but TimescaleDB's own
# files, in the layout CloudNativePG expects for an ImageVolume mount:
#
#   /lib              shared libraries
#   /share/extension  control file and SQL scripts
#
# Every TimescaleDB build the .deb provides is kept, not only TSDB_VERSION.
# PostgreSQL loads the shared library named by the version recorded in the
# catalog, so an image carrying only the newest build makes every hypertable
# query fail between the pod restart and `ALTER EXTENSION timescaledb UPDATE`:
#
#   ERROR:  could not access file "timescaledb-2.27.2": No such file or directory
#
# Keeping the older builds turns that into a non-disruptive upgrade.

ARG PG_MAJOR=18
ARG TSDB_VERSION=2.28.3
ARG BASE_IMAGE=ghcr.io/cloudnative-pg/postgresql:18-standard-trixie@sha256:f0cc49632b5cc1e51f65ba03658c89bd31d64ea2672b14843a808a8d281417e1

FROM ${BASE_IMAGE} AS build

ARG PG_MAJOR
ARG TSDB_VERSION

USER root
SHELL ["/bin/bash", "-eu", "-o", "pipefail", "-c"]

RUN test -d "/usr/lib/postgresql/${PG_MAJOR}" \
    || { echo "base image provides no PostgreSQL ${PG_MAJOR}" >&2; exit 1; }

# The package suite must match the base image's Debian release, so take the
# codename from the image rather than hardcoding it.
RUN . /etc/os-release; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl gnupg; \
    curl -fsSL https://packagecloud.io/timescale/timescaledb/gpgkey \
        | gpg --dearmor > /etc/apt/trusted.gpg.d/timescaledb.gpg; \
    echo "deb https://packagecloud.io/timescale/timescaledb/debian/ ${VERSION_CODENAME} main" \
        > /etc/apt/sources.list.d/timescaledb.list; \
    apt-get update; \
    pkg="timescaledb-2-postgresql-${PG_MAJOR}"; \
    ver="$(apt-cache madison "${pkg}" | awk -v p="${TSDB_VERSION}~" 'index($3, p) == 1 { print $3; exit }')"; \
    if [ -z "${ver}" ]; then \
        echo "no ${pkg} build for TimescaleDB ${TSDB_VERSION}, available:" >&2; \
        apt-cache madison "${pkg}" >&2; \
        exit 1; \
    fi; \
    echo "installing ${pkg}=${ver}"; \
    apt-get install -y --no-install-recommends "${pkg}=${ver}"

RUN lib="/usr/lib/postgresql/${PG_MAJOR}/lib"; \
    share="/usr/share/postgresql/${PG_MAJOR}/extension"; \
    mkdir -p /out/lib /out/share/extension; \
    cp "${lib}"/timescaledb*.so /out/lib/; \
    cp "${share}"/timescaledb.control /out/share/extension/; \
    cp "${share}"/timescaledb--*.sql /out/share/extension/; \
    test -f "/out/lib/timescaledb.so"; \
    test -f "/out/lib/timescaledb-${TSDB_VERSION}.so"; \
    test -f "/out/lib/timescaledb-tsl-${TSDB_VERSION}.so"; \
    test -f "/out/share/extension/timescaledb--${TSDB_VERSION}.sql"; \
    grep -Fqx "default_version = '${TSDB_VERSION}'" /out/share/extension/timescaledb.control

FROM scratch

ARG PG_MAJOR
ARG TSDB_VERSION

LABEL org.opencontainers.image.title="TimescaleDB extension for CloudNativePG"
LABEL org.opencontainers.image.description="TimescaleDB ${TSDB_VERSION} for PostgreSQL ${PG_MAJOR}, packaged for CloudNativePG ImageVolume mounts"
LABEL org.opencontainers.image.licenses="TSL-1.0"
LABEL org.opencontainers.image.version="${TSDB_VERSION}"

COPY --from=build /out/lib /lib
COPY --from=build /out/share /share
