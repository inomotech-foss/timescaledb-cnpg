#!/usr/bin/env bash
set -euo pipefail
node tests/timescaledb/check-versions.mjs
tests/timescaledb/verify.sh extension/timescaledb extension/timescaledb-toolkit

docker buildx build --output type=local,dest=previous/timescaledb -f - images/timescaledb <<'DOCKERFILE'
FROM ghcr.io/inomotech-foss/timescaledb-cnpg:2.31.0-pg18
DOCKERFILE
docker buildx build --output type=local,dest=previous/toolkit -f - images/timescaledb-toolkit <<'DOCKERFILE'
FROM ghcr.io/inomotech-foss/timescaledb-cnpg/toolkit:1.26.0-pg18
DOCKERFILE
tests/timescaledb/verify-upgrade.sh extension/timescaledb extension/timescaledb-toolkit previous/timescaledb previous/toolkit
