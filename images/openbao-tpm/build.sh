#!/usr/bin/env bash
set -euo pipefail

download() {
    curl -fsSL --retry 3 "$1" -o "$2"
    echo "$3  $2" | sha256sum -c -
}

export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig
export LD_LIBRARY_PATH=/usr/local/lib
mkdir -p /src /out/lib /out/plugins /out/licenses
cd /src

# Build against UBI's libc; Fedora binaries can require a newer glibc.
download "https://github.com/tpm2-software/tpm2-tss/releases/download/$TSS_VERSION/tpm2-tss-$TSS_VERSION.tar.gz" tss.tar.gz "$TSS_SHA256"
tar -xzf tss.tar.gz
cd "tpm2-tss-$TSS_VERSION"
./configure --prefix=/usr/local --libdir=/usr/local/lib \
    --disable-fapi --disable-policy --disable-doxygen-doc \
    --with-udevrulesdir=/tmp/udev --with-udevrulesprefix=70-
make -s -j"$(nproc)"
make -s install
cp LICENSE /out/licenses/tpm2-tss
cd /src

download "https://github.com/tpm2-software/tpm2-pkcs11/releases/download/$PKCS11_VERSION/tpm2-pkcs11-$PKCS11_VERSION.tar.gz" pkcs11.tar.gz "$PKCS11_SHA256"
tar -xzf pkcs11.tar.gz
cd "tpm2-pkcs11-$PKCS11_VERSION"
./configure --prefix=/usr/local --libdir=/usr/local/lib --disable-ptool-checks --without-fapi
make -s -j"$(nproc)"
make -s install
cp LICENSE /out/licenses/tpm2-pkcs11
cp -L /usr/local/lib/libtpm2_pkcs11.so /out/lib/
cp -L /usr/local/lib/libtss2-{esys,mu,rc,sys,tctildr,tcti-device,tcti-swtpm}.so.[0-9] /out/lib/
cd /src

case "$TARGETARCH" in
    amd64) variant=v1 ;;
    arm64) variant=v8 ;;
    *) echo "unsupported architecture: $TARGETARCH" >&2; exit 1 ;;
esac
asset="openbao-plugin-kms-pkcs11_linux_${TARGETARCH}_$variant"
base="https://github.com/openbao/openbao-plugins/releases/download/$KMS_VERSION"
download "$base/checksums-kms-pkcs11.txt" checksums.txt "$KMS_SHA256"
curl -fsSL --retry 3 "$base/$asset.tar.gz" -o "$asset.tar.gz"
grep "  $asset.tar.gz$" checksums.txt | sha256sum -c -
tar -xzf "$asset.tar.gz" "$asset" LICENSE
install -m 0755 "$asset" /out/plugins/openbao-plugin-kms-pkcs11
cp LICENSE /out/licenses/openbao-plugin-kms-pkcs11

# Include native dependencies and dynamically loaded TCTIs, retaining the
# official server image's loader and complete glibc family.
LD_LIBRARY_PATH=/out/lib ldd /out/lib/*.so* /out/plugins/* > dependencies.txt \
    || { cat dependencies.txt >&2; exit 1; }
if grep -q 'not found' dependencies.txt; then cat dependencies.txt >&2; exit 1; fi
awk '/=> \/.* \(/ {print $3}' dependencies.txt | sort -u > paths.txt
while IFS= read -r path; do
    case "$path" in /out/*|/usr/local/lib/*) continue ;; esac
    package=$(rpm -qf --qf '%{NAME}' "$(realpath "$path")")
    case "$package" in glibc) continue ;; esac
    cp -L "$path" /out/lib/
    rpm -ql "$package" | sed -n '\@^/usr/share/licenses/.*@p' > licenses.txt
    while IFS= read -r license; do
        if test -f "$license"; then cp --parents "$license" /out/licenses/; fi
    done < licenses.txt
done < paths.txt
cd /out
sha256sum plugins/openbao-plugin-kms-pkcs11 > plugins/SHA256SUMS
