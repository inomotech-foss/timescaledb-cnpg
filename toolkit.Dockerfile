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
# So the image carries the library of every packaged release from
# TOOLKIT_MIN_VERSION up to TOOLKIT_VERSION. Only TOOLKIT_VERSION, the tagged
# version, contributes its control file and SQL scripts.

ARG PG_MAJOR=18
ARG TOOLKIT_MIN_VERSION=1.22.0
ARG TOOLKIT_VERSION=1.23.0
ARG BASE_IMAGE=ghcr.io/cloudnative-pg/postgresql:18-standard-trixie@sha256:4e4ac3fb2c914cfb44f80f0b8be8aa550e83b80bf5220df49c3a8780c1f79bc8

FROM ${BASE_IMAGE} AS build

ARG PG_MAJOR
ARG TOOLKIT_MIN_VERSION
ARG TOOLKIT_VERSION

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
    le() { [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n 1)" = "$1" ]; }; \
    mkdir -p /out/lib /out/share/extension; \
    for v in $(apt-cache madison "${pkg}" \
            | awk '{ c=$3; sub(/^[0-9]+:/, "", c); sub(/~.*/, "", c); print c }' \
            | sort -uV); do \
        if ! le "${TOOLKIT_MIN_VERSION}" "${v}" || ! le "${v}" "${TOOLKIT_VERSION}"; then \
            continue; \
        fi; \
        ver="$(apt-cache madison "${pkg}" \
            | awk -v p="${v}~" '{ c=$3; sub(/^[0-9]+:/, "", c); if (index(c, p) == 1) { print $3; exit } }')"; \
        echo "downloading ${pkg}=${ver}"; \
        rm -rf ./extract ./*.deb; \
        apt-get download "${pkg}=${ver}"; \
        dpkg-deb -x ./*.deb ./extract; \
        cp "./extract/${lib}/timescaledb_toolkit-${v}.so" /out/lib/; \
        if [ "${v}" = "${TOOLKIT_VERSION}" ]; then \
            cp "./extract/${share}/timescaledb_toolkit.control" /out/share/extension/; \
            cp "./extract/${share}"/timescaledb_toolkit--*.sql /out/share/extension/; \
        fi; \
    done

RUN for v in "${TOOLKIT_MIN_VERSION}" "${TOOLKIT_VERSION}"; do \
        test -f "/out/lib/timescaledb_toolkit-${v}.so" || { \
            echo "no ${v} build of the toolkit was packaged" >&2; exit 1; }; \
    done; \
    test -f "/out/share/extension/timescaledb_toolkit--${TOOLKIT_VERSION}.sql"; \
    grep -Fqx "default_version = '${TOOLKIT_VERSION}'" /out/share/extension/timescaledb_toolkit.control

FROM scratch

ARG PG_MAJOR
ARG TOOLKIT_VERSION

LABEL org.opencontainers.image.title="TimescaleDB Toolkit extension for CloudNativePG"
LABEL org.opencontainers.image.description="TimescaleDB Toolkit for PostgreSQL ${PG_MAJOR}, packaged for CloudNativePG ImageVolume mounts"
LABEL org.opencontainers.image.licenses="TSL-1.0"
LABEL org.opencontainers.image.version="${TOOLKIT_VERSION}"

COPY --from=build /out/lib /lib
COPY --from=build /out/share /share
