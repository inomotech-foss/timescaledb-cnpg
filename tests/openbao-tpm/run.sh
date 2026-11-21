#!/usr/bin/env bash
set -euo pipefail

# Override only for local Podman tests; GitHub CI uses Docker.
docker() { command "${CONTAINER_ENGINE:-docker}" "$@"; }
extension=$(realpath extension/openbao-tpm)
# Let the upstream image's non-root UID traverse the local export directory.
chmod a+rx "$extension"
tests=$(realpath tests/openbao-tpm)
fixture="openbao-tpm-fixture-$$"
server="openbao-tpm-server-$$"
state="openbao-tpm-state-$$"
image=ghcr.io/openbao/openbao-ubi:2.7.2@sha256:822755226a0796a2ec18a395083c92e5ad57f49bf3ce4180a413b2361fac5c22

cleanup() {
    if [ "$?" -ne 0 ]; then docker logs "$server" >&2 2>/dev/null || true; fi
    docker rm -f "$server" "$fixture" >/dev/null 2>&1 || true
    docker volume rm "$state" >/dev/null 2>&1 || true
    docker image rm "$fixture" >/dev/null 2>&1 || true
}
trap cleanup EXIT
docker build -t "$fixture" "$tests"
docker volume create "$state" >/dev/null
docker run -d --name "$fixture" --network none \
    -v "$state:/state" -v "$tests:/tests:ro" -v "$extension:/extension:ro" "$fixture" >/dev/null
docker exec "$fixture" bash /tests/prepare.sh

# The server is the upstream image, unprivileged, without package installation.
docker run -d --name "$server" --user 100:1000 --read-only \
    --cap-drop ALL --security-opt no-new-privileges --tmpfs /tmp \
    --network "container:$fixture" -v "$state:/state" -v "$extension:/extension:ro" \
    -e BAO_HSM_PIN=test-user-pin --entrypoint bao "$image" \
    server -config=/state/openbao.hcl >/dev/null

api() { docker exec "$fixture" curl --silent --show-error --fail --max-time 60 "$@"; }
url=http://127.0.0.1:8200/v1
for _ in {1..60}; do
    if docker exec "$fixture" curl -s --max-time 2 "$url/sys/health" >/dev/null; then break; fi
    sleep 1
done
token=$(api -X PUT -d '{"recovery_shares":3,"recovery_threshold":2}' "$url/sys/init" | jq -er .root_token)
api -H "X-Vault-Token: $token" -X POST -d '{"type":"transit"}' "$url/sys/mounts/transit" >/dev/null
api -H "X-Vault-Token: $token" -X POST -d '{}' "$url/transit/keys/test" >/dev/null
ciphertext=$(api -H "X-Vault-Token: $token" -X POST \
    -d '{"plaintext":"dHBtLXNlYWwtdGVzdA=="}' "$url/transit/encrypt/test" | jq -er .data.ciphertext)
docker restart "$server" >/dev/null
for _ in {1..60}; do
    if api "$url/sys/health" >/dev/null 2>&1; then break; fi
    sleep 1
done
test "$(api "$url/sys/health" | jq -r .sealed)" = false
plaintext=$(api -H "X-Vault-Token: $token" -X POST \
    -d "{\"ciphertext\":\"$ciphertext\"}" "$url/transit/decrypt/test" | jq -er .data.plaintext)
test "$plaintext" = dHBtLXNlYWwtdGVzdA==
echo 'PASS: official OpenBao image auto-unseals after restart and decrypts transit data.'

# A missing TPM must fail closed rather than initializing another seal.
docker exec "$fixture" bash -c 'kill "$(cat /state/swtpm.pid)"'
docker restart "$server" >/dev/null
for _ in {1..30}; do
    if [ "$(docker inspect --format '{{.State.Running}}' "$server")" = false ]; then break; fi
    sleep 1
done
test "$(docker inspect --format '{{.State.Running}}' "$server")" = false
echo 'PASS: OpenBao refuses startup when its TPM is unavailable.'
