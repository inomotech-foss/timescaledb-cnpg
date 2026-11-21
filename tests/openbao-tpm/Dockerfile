FROM quay.io/fedora/fedora:44@sha256:fda16b8254a181b9f010930f16f0b33c8dc7cb680a8f6c934bc9da5b3c3a5fed
RUN dnf install -y --setopt=install_weak_deps=False \
      curl dbus-daemon jq opensc swtpm tpm2-abrmd tpm2-pkcs11-tools-1.10.1 tpm2-tools \
    && dnf clean all
CMD ["sleep", "infinity"]
