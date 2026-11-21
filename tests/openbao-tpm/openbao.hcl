disable_mlock = true
ui = false
api_addr = "http://127.0.0.1:8200"
cluster_addr = "https://127.0.0.1:8201"
storage "raft" {
  path = "/state/raft"
  node_id = "test"
}
listener "tcp" {
  address = "127.0.0.1:8200"
  tls_disable = true
}
plugin_directory = "/extension/plugins"
plugin_auto_download = false
plugin "kms" "pkcs11" {
  command = "openbao-plugin-kms-pkcs11"
  sha256sum = "PLUGIN_SHA256"
  env = [
    "LD_LIBRARY_PATH=/extension/lib",
    "TPM2_PKCS11_TCTI=swtpm:host=127.0.0.1,port=2321",
    "TPM2_PKCS11_STORE=/state/tokens",
  ]
}
seal "pkcs11" {
  lib = "/extension/lib/libtpm2_pkcs11.so"
  token_label = "test"
  key_label = "seal"
  mechanism = "RSA_PKCS_OAEP"
  rsa_oaep_hash = "sha256"
}
