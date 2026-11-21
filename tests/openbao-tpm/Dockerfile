FROM quay.io/fedora/fedora:44@sha256:dbd1c4c85bb49e385476b5262e2e8e336d1da056772239d09cf177d700d598b8
RUN dnf install -y --setopt=install_weak_deps=False \
      curl dbus-daemon jq opensc swtpm tpm2-abrmd tpm2-pkcs11-tools-1.10.1 tpm2-tools \
    && dnf clean all
CMD ["sleep", "infinity"]
