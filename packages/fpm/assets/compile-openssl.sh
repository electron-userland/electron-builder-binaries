#!/usr/bin/env bash
# Builds a static OpenSSL (3.5 LTS) for the Linux portable Ruby.
#
# Debian buster's libssl1.1 (OpenSSL 1.1.1n) is end-of-life, but buster is kept as
# the build image so the bundle's glibc floor stays at 2.28. Building OpenSSL from
# source here and linking it statically into Ruby's openssl extension means no
# libssl/libcrypto shared objects are shipped, and the glibc floor is unchanged.
#
# Output: $OPENSSL_PREFIX/{include,lib/libssl.a,lib/libcrypto.a,lib/pkgconfig}
#         $OPENSSL_PREFIX/LICENSE.txt

set -euo pipefail

# renovate: datasource=github-releases depName=openssl/openssl extractVersion=^openssl-(?<version>.+)$
OPENSSL_VERSION="${OPENSSL_VERSION:-3.5.9}"
# SHA256 of https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz
# Re-pin when bumping OPENSSL_VERSION (compare against the .sha256 file published next to the tarball).
OPENSSL_SHA256="${OPENSSL_SHA256:-603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a}"
OPENSSL_PREFIX="${OPENSSL_PREFIX:-/opt/openssl}"
TARGET_ARCH="${TARGET_ARCH:-$(uname -m)}"

if [ "$(uname)" != "Linux" ]; then
    echo "❌ compile-openssl.sh is only used for the Linux build" >&2
    exit 1
fi

# The i386 image runs on an x86_64 kernel, so `uname -m` (which OpenSSL's ./config
# relies on) reports x86_64. Pick the Configure target from TARGET_ARCH instead.
case "$TARGET_ARCH" in
    amd64 | x86_64) OPENSSL_TARGET="linux-x86_64" ;;
    i386 | i686) OPENSSL_TARGET="linux-x86" ;;
    arm64* | aarch64) OPENSSL_TARGET="linux-aarch64" ;;
    arm/v7 | armv7*) OPENSSL_TARGET="linux-armv4" ;;
    *)
        echo "❌ Unsupported TARGET_ARCH for OpenSSL: $TARGET_ARCH" >&2
        exit 1
        ;;
esac

SRC_DIR="$(mktemp -d)"
trap 'rm -rf "$SRC_DIR"' EXIT
cd "$SRC_DIR"

TARBALL="openssl-${OPENSSL_VERSION}.tar.gz"
echo "⬇️ Downloading OpenSSL $OPENSSL_VERSION source..."
curl -fsSL --retry 3 --retry-delay 2 --max-time 300 \
    "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/${TARBALL}" \
    -o "$TARBALL"
echo "  🔍 Verifying OpenSSL source checksum..."
actual=$(sha256sum "$TARBALL" | awk '{print $1}')
if [ "$actual" != "$OPENSSL_SHA256" ]; then
    echo "❌ Checksum mismatch for $TARBALL" >&2
    echo "   expected: $OPENSSL_SHA256" >&2
    echo "   actual:   $actual" >&2
    exit 1
fi
echo "  ✓ Checksum verified"
tar -xzf "$TARBALL"
cd "openssl-${OPENSSL_VERSION}"

# no-shared      static libssl.a/libcrypto.a only, linked into the ruby binary
# no-module      build the legacy provider into libcrypto rather than as a loadable module
# -fPIC          the static libs end up in a PIE executable (buster's gcc defaults to PIE)
# --openssldir   Debian's location, so the default CA path (/usr/lib/ssl/certs) matches
#                what the previous libssl1.1 build used on Debian/Ubuntu hosts
# --libdir=lib   keep lib/ rather than lib64/ on 64-bit targets
echo "⚙️ Configuring OpenSSL ($OPENSSL_TARGET)..."
./Configure "$OPENSSL_TARGET" \
    no-shared no-module no-tests no-docs no-apps \
    -fPIC \
    --prefix="$OPENSSL_PREFIX" \
    --libdir=lib \
    --openssldir=/usr/lib/ssl \
    1>/dev/null

echo "🔨 Building OpenSSL..."
make -j"$(nproc)" build_libs 1>/dev/null
echo "⤵️ Installing OpenSSL to $OPENSSL_PREFIX..."
make install_dev 1>/dev/null
cp LICENSE.txt "$OPENSSL_PREFIX/LICENSE.txt"

if ls "$OPENSSL_PREFIX"/lib/*.so* >/dev/null 2>&1; then
    echo "❌ Shared OpenSSL libraries were built; expected static only" >&2
    exit 1
fi
echo "✅ OpenSSL $OPENSSL_VERSION installed (static) to $OPENSSL_PREFIX"
