# syntax=docker/dockerfile:1

# TimescaleDB Toolkit packaged as a CloudNativePG extension image.
#
# Its own image rather than part of the TimescaleDB one: CloudNativePG mounts one
# image per entry in spec.postgresql.extensions, at /extensions/<name>, and the
# extension name here is timescaledb_toolkit.
#
# Unlike timescaledb, which ships every historical build in one .deb, the toolkit
# .deb ships exactly one library named for its version and no unversioned
# fallback. An image with only the newest build therefore breaks every toolkit
# call between the pod restart and `ALTER EXTENSION timescaledb_toolkit UPDATE`:
#
#   ERROR:  could not access file "timescaledb_toolkit-1.22.0": No such file or directory
#
# TOOLKIT_VERSIONS is a list, oldest first. Every entry contributes its library;
# the last is the tagged version and the only one whose SQL scripts are kept.

ARG PG_MAJOR=18
ARG TOOLKIT_VERSIONS="1.22.0 1.23.0"
ARG BASE_IMAGE=ghcr.io/cloudnative-pg/postgresql:18-standard-trixie@sha256:f0cc49632b5cc1e51f65ba03658c89bd31d64ea2672b14843a808a8d281417e1

FROM ${BASE_IMAGE} AS build

ARG PG_MAJOR
ARG TOOLKIT_VERSIONS

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
    apt-get update

# Extracted from the .deb rather than installed, so several versions can each
# contribute a library without apt fighting over the path. Toolkit versions carry
# a Debian epoch (1:1.23.0~debian13) that is not part of the upstream version, so
# it is stripped before matching and kept when asking apt for the exact build.
WORKDIR /tmp/debs

RUN pkg="timescaledb-toolkit-postgresql-${PG_MAJOR}"; \
    lib="usr/lib/postgresql/${PG_MAJOR}/lib"; \
    share="usr/share/postgresql/${PG_MAJOR}/extension"; \
    mkdir -p /out/lib /out/share/extension; \
    for v in ${TOOLKIT_VERSIONS}; do \
        ver="$(apt-cache madison "${pkg}" \
            | awk -v p="${v}~" '{ c=$3; sub(/^[0-9]+:/, "", c); if (index(c, p) == 1) { print $3; exit } }')"; \
        if [ -z "${ver}" ]; then \
            echo "no ${pkg} build for toolkit ${v}, available:" >&2; \
            apt-cache madison "${pkg}" >&2; \
            exit 1; \
        fi; \
        echo "downloading ${pkg}=${ver}"; \
        rm -rf ./extract ./*.deb; \
        apt-get download "${pkg}=${ver}"; \
        dpkg-deb -x ./*.deb ./extract; \
        cp "./extract/${lib}/timescaledb_toolkit-${v}.so" /out/lib/; \
        rm -rf /out/share/extension; \
        mkdir -p /out/share/extension; \
        cp "./extract/${share}/timescaledb_toolkit.control" /out/share/extension/; \
        cp "./extract/${share}"/timescaledb_toolkit--*.sql /out/share/extension/; \
    done

RUN set -- ${TOOLKIT_VERSIONS}; \
    for v in "$@"; do test -f "/out/lib/timescaledb_toolkit-${v}.so"; done; \
    for v in "$@"; do latest="${v}"; done; \
    test -f "/out/share/extension/timescaledb_toolkit--${latest}.sql"; \
    grep -Fqx "default_version = '${latest}'" /out/share/extension/timescaledb_toolkit.control

FROM scratch

ARG PG_MAJOR
ARG TOOLKIT_VERSIONS

LABEL org.opencontainers.image.title="TimescaleDB Toolkit extension for CloudNativePG"
LABEL org.opencontainers.image.description="TimescaleDB Toolkit for PostgreSQL ${PG_MAJOR}, packaged for CloudNativePG ImageVolume mounts"
LABEL org.opencontainers.image.licenses="TSL-1.0"

COPY --from=build /out/lib /lib
COPY --from=build /out/share /share
