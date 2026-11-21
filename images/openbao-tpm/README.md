# OpenBao TPM extension

PKCS#11 KMS plugin, tpm2-pkcs11 and native dependencies for the official
`ghcr.io/openbao/openbao-ubi` image (UBI 10, amd64/arm64).

Mount the image at `/extension`. It contains `/plugins`, `/lib` and `/licenses`.
Read the plugin hash from `/extension/plugins/SHA256SUMS` and configure:

```hcl
plugin_directory = "/extension/plugins"
plugin_auto_download = false
plugin "kms" "pkcs11" {
  command = "openbao-plugin-kms-pkcs11"
  sha256sum = "<hash from SHA256SUMS>"
  env = [
    "LD_LIBRARY_PATH=/extension/lib",
    "TPM2_PKCS11_TCTI=device:/dev/tpmrm0",
    "TPM2_PKCS11_STORE=/openbao/data/tokens",
  ]
}
seal "pkcs11" {
  lib = "/extension/lib/libtpm2_pkcs11.so"
  token_label = "openbao"
  key_label = "seal"
  mechanism = "RSA_PKCS_OAEP"
  rsa_oaep_hash = "sha256"
}
```

Provision the token and RSA key before initializing OpenBao; supply its user PIN
as `BAO_HSM_PIN`. Persist the token store and grant OpenBao access to `/dev/tpmrm0`.
See [OpenBao's PKCS#11 seal](https://openbao.org/docs/configuration/seal/pkcs11/).

CI mounts the artifact into the upstream server image with a disposable software
TPM. It checks restart auto-unseal, transit decryption and failure without the TPM.
