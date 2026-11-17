#!/usr/bin/env bash
# Usage: verify-upgrade.sh <new-timescaledb> <new-toolkit> <old-timescaledb> <old-toolkit>
set -euo pipefail

if [ "$#" -ne 4 ]; then
    echo "usage: $0 <new-timescaledb> <new-toolkit> <old-timescaledb> <old-toolkit>" >&2
    exit 2
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
old_tsdb="$(sed -n "s/^default_version = '\([^']*\)'/\1/p" "$3/share/extension/timescaledb.control")"
old_toolkit="$(sed -n "s/^default_version = '\([^']*\)'/\1/p" "$4/share/extension/timescaledb_toolkit.control")"
test -n "${old_tsdb}"
test -n "${old_toolkit}"

volume="$(docker volume create)"
trap 'docker volume rm "${volume}" > /dev/null' EXIT
export VERIFY_DATA_VOLUME="${volume}"

VERIFY_MODE=upgrade-seed VERIFY_TSDB_VERSION="${old_tsdb}" VERIFY_TOOLKIT_VERSION="${old_toolkit}" \
    "${repo_root}/hack/verify.sh" "$3" "$4"
VERIFY_MODE=upgrade "${repo_root}/hack/verify.sh" "$1" "$2"
