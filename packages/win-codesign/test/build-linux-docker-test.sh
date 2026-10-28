#!/usr/bin/env bash
# Runs the Linux bundle tests in a clean ubuntu:24.04 container, which has no OpenSSL 1.1
# (the 1.3.x bundles failed there with "libcrypto.so.1.1: cannot open shared object file"):
#   - verify-bundle-licenses.sh (on the host): every binary ships its license
#   - build-linux-test.sh: contents, licenses, linkage, RUNPATH, legacy PKCS#12 / PEM sign + verify
#   - pkcs11-sign-test.sh: SoftHSM-backed PKCS#11 signing (amd64 / arm64; Ubuntu 24.04 has
#     no i386 softhsm2 package)
#
# The i386 bundle runs in the amd64 image with the i386 glibc and zlib added.
# Run: bash packages/win-codesign/test/build-linux-docker-test.sh <win-codesign-linux-<arch>.zip> <amd64|arm64|i386>
# Env: TEST_IMAGE (default ubuntu:24.04)
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <bundle.zip> <amd64|arm64|i386>" >&2
    exit 2
fi

ZIP="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
ARCH="$2"
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(cd "$TEST_DIR/.." && pwd)"
TEST_IMAGE="${TEST_IMAGE:-ubuntu:24.04}"

case "$ARCH" in
    amd64) PLATFORM="linux/amd64"; PKCS11=1 ;;
    arm64) PLATFORM="linux/arm64"; PKCS11=1 ;;
    i386)  PLATFORM="linux/amd64"; PKCS11=0 ;;
    *) echo "❌ Unsupported arch: $ARCH" >&2; exit 2 ;;
esac

# Every binary in the zip ships its license (the guard, scripts/verify-licenses.sh, is not mounted in the container).
bash "$PKG_DIR/assets/verify-bundle-licenses.sh" "$ZIP"

docker run --rm --platform "$PLATFORM" \
    -e ARCH="$ARCH" -e PKCS11="$PKCS11" \
    -v "$PKG_DIR:/pkg:ro" -v "$ZIP:/bundle.zip:ro" \
    "$TEST_IMAGE" bash -euo pipefail -c '
        export DEBIAN_FRONTEND=noninteractive
        pkgs=(unzip openssl binutils)
        [[ "$PKCS11" == 1 ]] && pkgs+=(softhsm2)
        if [[ "$ARCH" == i386 ]]; then
            dpkg --add-architecture i386
            pkgs+=(libc6:i386 zlib1g:i386)
        fi
        apt-get update -qq
        apt-get install -y -qq --no-install-recommends "${pkgs[@]}" >/dev/null

        if ldconfig -p | grep -q "libcrypto\.so\.1\.1"; then
            echo "❌ test image unexpectedly provides libcrypto.so.1.1" >&2
            exit 1
        fi
        echo "ℹ️  system OpenSSL: $(openssl version)"

        mkdir -p /tmp/bundle
        unzip -q /bundle.zip -d /tmp/bundle
        bash /pkg/test/build-linux-test.sh /tmp/bundle
        if [[ "$PKCS11" == 1 ]]; then
            bash /pkg/test/pkcs11-sign-test.sh /tmp/bundle
        else
            echo "⏭  PKCS#11 test skipped for $ARCH"
        fi
    '
