#!/usr/bin/env bash
# Disposable software TPM only; no host devices are passed to this fixture.
set -euo pipefail
umask 077
export TPM2TOOLS_TCTI=swtpm:host=127.0.0.1,port=2321
export TPM2_PKCS11_TCTI=$TPM2TOOLS_TCTI
export TPM2_PKCS11_STORE=/state/tokens

mkdir -p /state/{swtpm,tokens,raft}
swtpm socket --tpm2 --tpmstate dir=/state/swtpm \
    --server type=tcp,port=2321 --ctrl type=tcp,port=2322 \
    --flags not-need-init --pid file=/state/swtpm.pid --daemon
tpm2_startup -c
# Provisioning invokes several tools; give the emulator a resource manager,
# equivalent to /dev/tpmrm0 on a real node.
DBUS_SESSION_BUS_ADDRESS=$(dbus-daemon --session --fork --print-address=1)
export DBUS_SESSION_BUS_ADDRESS
tpm2-abrmd --allow-root --session --tcti="$TPM2TOOLS_TCTI" > /state/abrmd.log 2>&1 &
manager=$!
export TPM2TOOLS_TCTI=tabrmd:bus_type=session
export TPM2_PKCS11_TCTI=$TPM2TOOLS_TCTI
for _ in {1..30}; do
    if ! kill -0 "$manager" 2>/dev/null; then cat /state/abrmd.log >&2; exit 1; fi
    if timeout 2 tpm2_getcap properties-fixed >/dev/null 2>&1; then break; fi
    sleep 1
done
tpm2_ptool init --path "$TPM2_PKCS11_STORE"
tpm2_ptool addtoken --path "$TPM2_PKCS11_STORE" --pid 1 \
    --label test --sopin test-so-pin --userpin test-user-pin
tpm2_ptool addkey --path "$TPM2_PKCS11_STORE" --label test \
    --key-label seal --algorithm rsa2048 --userpin test-user-pin
kill "$manager"
wait "$manager" || true
tpm2_flushcontext -T swtpm:host=127.0.0.1,port=2321 -t

digest=$(cut -d ' ' -f 1 /extension/plugins/SHA256SUMS)
sed "s/PLUGIN_SHA256/$digest/" /tests/openbao.hcl > /state/openbao.hcl
chown -R 100:1000 /state
