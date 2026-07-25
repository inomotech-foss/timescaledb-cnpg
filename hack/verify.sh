#!/usr/bin/env bash
# Load an extension tree into a stock CloudNativePG PostgreSQL image and check
# that the TimescaleDB Community features work.
#
#   docker buildx build -o type=local,dest=extension .
#   hack/verify.sh extension
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: $0 <extension-dir>" >&2
    exit 2
fi

ext_dir="$(cd "$1" && pwd)"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"

# buildx creates its local output directory 0700. PostgreSQL runs as uid 26 in
# the container below and has to traverse it. Docker Desktop papers over this
# on macOS, a Linux host does not.
chmod -R a+rX "${ext_dir}"

arg() { sed -n "s/^ARG $1=//p" "${repo_root}/Dockerfile"; }

base_image="$(arg BASE_IMAGE)"
tsdb_version="$(arg TSDB_VERSION)"

# The shared libraries are built for linux/amd64, so the base image has to
# match. `docker run` rejects the repo:tag@digest form that Renovate keeps in
# the Dockerfile, and refuses a manifest-list digest together with --platform,
# so resolve the amd64 manifest explicitly.
repo="${base_image%@*}"
if [[ "${repo##*/}" == *:* ]]; then
    repo="${repo%:*}"
fi

amd64_digest="$(docker buildx imagetools inspect "${base_image}" --format \
    '{{- range .Manifest.Manifests -}}
       {{- if and (eq .Platform.OS "linux") (eq .Platform.Architecture "amd64") -}}
         {{- .Digest -}}
       {{- end -}}
     {{- end -}}')"

if [ -n "${amd64_digest}" ]; then
    run_image="${repo}@${amd64_digest}"
else
    run_image="${base_image}"
fi

echo "extension tree:   ${ext_dir}"
echo "base image:       ${run_image}"
echo "expected version: ${tsdb_version}"
echo

exec docker run --rm \
    --platform linux/amd64 \
    --user 26 \
    --env "TSDB_VERSION=${tsdb_version}" \
    --volume "${ext_dir}:/extensions/timescaledb:ro" \
    --volume "${repo_root}/hack:/hack:ro" \
    --entrypoint /hack/verify-inner.sh \
    "${run_image}"
