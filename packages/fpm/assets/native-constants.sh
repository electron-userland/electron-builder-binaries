#!/usr/bin/env bash
# Shared configuration for the native tools the fpm toolset ships in its root bin/ (xz, and rpm/rpmbuild
# from packages/rpm). Sourced, not executed.
# shellcheck disable=SC2034 # variables are consumed by the scripts that source this file

# XZ Utils: https://github.com/tukaani-project/xz/releases/tag/v5.8.4
# The tarball is signed by Lasse Collin (OpenPGP key 3690C240CE51B4670D30AD1C38EE757D69184620). To re-pin:
#   curl -fsSLO "$XZ_URL" && curl -fsSLO "$XZ_URL.sig"
#   gpg --verify "xz-$XZ_VERSION.tar.gz.sig" "xz-$XZ_VERSION.tar.gz"   # must say: Good signature from "Lasse Collin"
#   sha256sum "xz-$XZ_VERSION.tar.gz"
XZ_VERSION="${XZ_VERSION:-5.8.4}"
XZ_SHA256="${XZ_SHA256:-0014c7886930454fe8bd4228665b51af55eeae560ea135c9c4cd33f55b2591d9}"
XZ_URL="${XZ_URL:-https://github.com/tukaani-project/xz/releases/download/v${XZ_VERSION}/xz-${XZ_VERSION}.tar.gz}"

# Linux build images. rpm (amd64, arm64) and xz are built on manylinux_2_28 (AlmaLinux 8, glibc 2.28),
# the same floor as the Ruby build (Debian buster). manylinux_2_28 has no i686 image, so the i386 xz is
# built on manylinux2014 (CentOS 7, glibc 2.17) and i386 ships no rpm.
NATIVE_IMAGE_amd64="${NATIVE_IMAGE_amd64:-quay.io/pypa/manylinux_2_28_x86_64:latest}"
NATIVE_IMAGE_arm64="${NATIVE_IMAGE_arm64:-quay.io/pypa/manylinux_2_28_aarch64:latest}"
NATIVE_IMAGE_i386="${NATIVE_IMAGE_i386:-quay.io/pypa/manylinux2014_i686:latest}"
