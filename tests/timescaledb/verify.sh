#!/usr/bin/env bash
# Load extension trees into a stock CloudNativePG PostgreSQL image and check
# that the TimescaleDB Community features work.
#
#   docker buildx build -o type=local,dest=extension images/timescaledb
#   tests/timescaledb/verify.sh extension
#
# Optionally verify the toolkit alongside it, which is how the two are meant to
# be mounted:
#
#   docker buildx build -o type=local,dest=toolkit images/timescaledb-toolkit
#   tests/timescaledb/verify.sh extension toolkit
#
# The trees are architecture-specific and default to the host's. Set
# VERIFY_PLATFORM to check a tree built for another one, which needs QEMU.
set -euo pipefail

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "usage: $0 <timescaledb-dir> [toolkit-dir]" >&2
    exit 2
fi

ext_dir="$(cd "$1" && pwd)"
toolkit_dir=""
if [ $# -eq 2 ]; then
    toolkit_dir="$(cd "$2" && pwd)"
fi
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"

# buildx creates its local output directory 0700. PostgreSQL runs as uid 26 in
# the container below and has to traverse it. Docker Desktop papers over this
# on macOS, a Linux host does not.
chmod -R a+rX "${ext_dir}"
if [ -n "${toolkit_dir}" ]; then
    chmod -R a+rX "${toolkit_dir}"
fi

arg() { sed -n "s/^ARG $1=//p" "${repo_root}/images/timescaledb/Dockerfile"; }

base_image="$(arg BASE_IMAGE)"
tsdb_version="${VERIFY_TSDB_VERSION:-$(arg TSDB_VERSION)}"
toolkit_version="${VERIFY_TOOLKIT_VERSION:-$(sed -n 's/^ARG TOOLKIT_VERSION=//p' "${repo_root}/images/timescaledb-toolkit/Dockerfile")}"

platform="${VERIFY_PLATFORM:-linux/$(docker version --format '{{.Server.Arch}}')}"
platform_os="${platform%%/*}"
platform_arch="${platform##*/}"

# `docker run` rejects the repo:tag@digest form that Renovate keeps in the
# Dockerfile, and refuses a manifest-list digest together with --platform, so
# resolve the single-platform manifest explicitly.
repo="${base_image%@*}"
if [[ "${repo##*/}" == *:* ]]; then
    repo="${repo%:*}"
fi

digest="$(docker buildx imagetools inspect "${base_image}" --format \
    '{{- range .Manifest.Manifests -}}
       {{- if and (eq .Platform.OS "'"${platform_os}"'") (eq .Platform.Architecture "'"${platform_arch}"'") -}}
         {{- .Digest -}}
       {{- end -}}
     {{- end -}}')"

if [ -n "${digest}" ]; then
    run_image="${repo}@${digest}"
else
    run_image="${base_image}"
fi

echo "extension tree:   ${ext_dir}"
if [ -n "${toolkit_dir}" ]; then
    echo "toolkit tree:     ${toolkit_dir}"
fi
echo "base image:       ${run_image}"
echo "platform:         ${platform}"
echo "expected version: ${tsdb_version}"
echo

mounts=(--volume "${ext_dir}:/extensions/timescaledb:ro")
if [ -n "${toolkit_dir}" ]; then
    mounts+=(--volume "${toolkit_dir}:/extensions/timescaledb_toolkit:ro")
fi
if [ -n "${VERIFY_DATA_VOLUME:-}" ]; then
    mounts+=(--volume "${VERIFY_DATA_VOLUME}:/tmp/pgdata")
    if [ "${VERIFY_MODE:-fresh}" = upgrade-seed ]; then
        docker run --rm --platform "${platform}" --user 0 \
            --volume "${VERIFY_DATA_VOLUME}:/tmp/pgdata" \
            --entrypoint /bin/chown "${run_image}" 26:26 /tmp/pgdata
    fi
fi

exec docker run --rm \
    --platform "${platform}" \
    --user 26 \
    --env "TSDB_VERSION=${tsdb_version}" \
    --env "TOOLKIT_VERSION=${toolkit_version}" \
    --env "VERIFY_MODE=${VERIFY_MODE:-fresh}" \
    "${mounts[@]}" \
    --volume "${repo_root}/tests/timescaledb:/tests:ro" \
    --entrypoint /tests/verify-inner.sh \
    "${run_image}"
