# syntax=docker/dockerfile:1.29.0@sha256:572cebbc2b15e6f84c077742952674889cb63cd5e9b80abdffcbe587b6f19183

ARG BASE_IMAGE=registry.access.redhat.com/ubi10/ubi:10.1@sha256:15f0a6e2b448ac7aa24425c9ab541e6402dc32b782844a285ccaeffb1c938fe1
ARG PKCS11_VERSION=1.10.1
ARG PKCS11_SHA256=f3315d17811f918779a1046ba20e49060a40b2b586a06ab013ff8c8da53752e4
ARG TSS_VERSION=4.1.5
ARG TSS_SHA256=992fef60ce3debcba1775249b4bba88c22c17969474336cd70390700a988af8b
ARG KMS_VERSION=kms-pkcs11-v0.2.1
ARG KMS_SHA256=37992fe6d93695683af453458f0cbf1fdc724efe761197c06aa094c4066d18a6
ARG REVISION=1

FROM ${BASE_IMAGE} AS build
ARG TARGETARCH
ARG PKCS11_VERSION
ARG PKCS11_SHA256
ARG TSS_VERSION
ARG TSS_SHA256
ARG KMS_VERSION
ARG KMS_SHA256

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]
RUN dnf install -y --setopt=install_weak_deps=False \
      autoconf-archive automake gcc libtool libyaml-devel make \
      openssl-devel pkgconf-pkg-config sqlite-devel tar gzip \
    && dnf clean all
COPY build.sh /build.sh
RUN bash /build.sh

FROM scratch
ARG PKCS11_VERSION
ARG KMS_VERSION
LABEL org.opencontainers.image.title="TPM 2.0 PKCS#11 extension for OpenBao UBI 10"
LABEL org.opencontainers.image.source="https://github.com/inomotech-foss/extension-images"
LABEL org.opencontainers.image.licenses="BSD-2-Clause AND MPL-2.0 AND Apache-2.0 AND MIT AND Zlib AND blessing"
LABEL org.opencontainers.image.version="${PKCS11_VERSION}-${KMS_VERSION}"
COPY --from=build /out/ /
COPY LICENSE.zlib-ng /licenses/zlib-ng
