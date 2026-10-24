#!/usr/bin/env bash
# Builds the self-contained Linux osslsigncode bundle. Runs inside the Ubuntu 20.04 builder
# image from assets/Dockerfile (glibc 2.31 baseline), mirroring build-mac.sh:
#
#   - OpenSSL (assets/deps-versions.sh) built shared and shipped in lib/
#   - libp11's pkcs11prov provider built against it and shipped in lib/ossl-modules
#   - osslsigncode linked against that OpenSSL with RUNPATH $ORIGIN/../lib
#
# With OpenSSL 3 osslsigncode uses OpenSSL's own HTTP client, so it no longer links libcurl.
# The previous builds linked the image's libcrypto.so.1.1 + libcurl.so.4 and shipped an empty
# lib/, so the binary did not start on distros without OpenSSL 1.1 (Ubuntu 22.04 and later).
set -euo pipefail

ASSETS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat >&2 << EOF
Usage: $0 [options]
  --arch              Target architecture: amd64, arm64, i386 (default: \$PLATFORM_ARCH or 'amd64')
  --osslsigncode-ver  osslsigncode version tag to build (default: \$OSSLSIGNCODE_VER or '2.11')
  --output-dir        Directory to write the ZIP bundle to (default: /out/linux/osslsigncode)
  -h|--help           Show this help
EOF
    exit 1
}

PLATFORM_ARCH="${PLATFORM_ARCH:-amd64}"
OSSLSIGNCODE_VER="${OSSLSIGNCODE_VER:-2.11}"
OUTPUT_DIR="/out/linux/osslsigncode"
# Oldest glibc the bundle may require: that of the Ubuntu 20.04 builder image.
MAX_GLIBC="${MAX_GLIBC:-2.31}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)             PLATFORM_ARCH="$2";    shift 2 ;;
        --osslsigncode-ver) OSSLSIGNCODE_VER="$2"; shift 2 ;;
        --output-dir)       OUTPUT_DIR="$2";       shift 2 ;;
        -h|--help)          usage ;;
        *)                  echo "❌ Unknown argument: $1" >&2; usage ;;
    esac
done

# shellcheck source=deps-versions.sh
source "$ASSETS_DIR/deps-versions.sh"

# i386 is built on amd64 with gcc-multilib (-m32).
CMAKE_ARCH_FLAGS=()
LIBP11_HOST=()
M32=""
case "$PLATFORM_ARCH" in
    amd64|x86_64)  PLATFORM_ARCH="amd64"; OPENSSL_TARGET="linux-x86_64" ;;
    arm64|aarch64) PLATFORM_ARCH="arm64"; OPENSSL_TARGET="linux-aarch64" ;;
    i386|ia32|i686)
        PLATFORM_ARCH="i386"
        OPENSSL_TARGET="linux-x86" # adds -m32
        M32="-m32"
        LIBP11_HOST=(--host=i686-linux-gnu)
        read -r -a CMAKE_ARCH_FLAGS <<< "$(bash "$ASSETS_DIR/compiler-flags.sh" --arch i386)"
        CMAKE_ARCH_FLAGS+=(-DCMAKE_PREFIX_PATH=/usr/lib/i386-linux-gnu)
        export PKG_CONFIG_PATH=/usr/lib/i386-linux-gnu/pkgconfig
        ;;
    *) echo "❌ Error: unsupported arch: $PLATFORM_ARCH" >&2; exit 1 ;;
esac

NCPU="$(nproc)"
TMP_DIR="$(mktemp -d /tmp/win-codesign-linux-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "=================================================="
echo "Building osslsigncode $OSSLSIGNCODE_VER for Linux $PLATFORM_ARCH"
echo "  OpenSSL: $OPENSSL_VER ($OPENSSL_TARGET)"
echo "  libp11:  $LIBP11_VER"
echo "=================================================="

fetch_verified() {
    local url="$1" sha256="$2" out="$3"
    curl -fsSL --retry 3 --retry-delay 2 "$url" -o "$out"
    echo "$sha256  $out" | sha256sum -c -
}

# ── OpenSSL (bundled) ─────────────────────────────────────────────────────────
# Same configuration as build-mac.sh:
#   shared     pkcs11prov must share one libcrypto with osslsigncode (a static osslsigncode
#              plus an external provider crashes in OPENSSL_cleanup at exit)
#   no-module  compile the legacy provider into libcrypto, so `-pkcs12` files using
#              RC2/3DES load without an ossl-modules entry
#   --openssldir=/etc/ssl  root-owned system location for openssl.cnf
#   --prefix   only used for the compiled-in default MODULESDIR/ENGINESDIR, so it must be a
#              path regular users cannot create; the libs are staged with DESTDIR
#   --libdir=lib  keep linux-x86_64 from using lib64
OPENSSL_RUNTIME_PREFIX="/opt/win-codesign-openssl"
OPENSSL_DESTDIR="$TMP_DIR/openssl-destdir"
OPENSSL_PREFIX="$OPENSSL_DESTDIR$OPENSSL_RUNTIME_PREFIX"
OPENSSL_LIBDIR="$OPENSSL_PREFIX/lib"
fetch_verified "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VER/openssl-$OPENSSL_VER.tar.gz" \
    "$OPENSSL_SHA256" "$TMP_DIR/openssl.tar.gz"
tar -xzf "$TMP_DIR/openssl.tar.gz" -C "$TMP_DIR"
(
    cd "$TMP_DIR/openssl-$OPENSSL_VER"
    ./Configure "$OPENSSL_TARGET" \
        shared no-module no-tests no-docs no-apps \
        --prefix="$OPENSSL_RUNTIME_PREFIX" \
        --openssldir=/etc/ssl \
        --libdir=lib
    make -j"$NCPU" build_libs
    make install_dev DESTDIR="$OPENSSL_DESTDIR"
)
# Only the shared libraries may be linked.
rm -f "$OPENSSL_LIBDIR"/*.a

# ── libp11 pkcs11prov provider ────────────────────────────────────────────────
LIBP11_PREFIX="$TMP_DIR/libp11-install"
fetch_verified "https://github.com/OpenSC/libp11/releases/download/libp11-$LIBP11_VER/libp11-$LIBP11_VER.tar.gz" \
    "$LIBP11_SHA256" "$TMP_DIR/libp11.tar.gz"
tar -xzf "$TMP_DIR/libp11.tar.gz" -C "$TMP_DIR"
# The empty --with-pkcs11-module keeps configure from baking the build image's p11-kit proxy
# into pkcs11prov as its default PKCS#11 module. configure only builds pkcs11prov when
# pkg-config reports libcrypto 3.x, so point it at the bundled OpenSSL's .pc files.
(
    cd "$TMP_DIR/libp11-$LIBP11_VER"
    PKG_CONFIG_PATH="$OPENSSL_LIBDIR/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" \
    ./configure "${LIBP11_HOST[@]}" \
        --prefix="$LIBP11_PREFIX" \
        --with-modulesdir="$LIBP11_PREFIX/ossl-modules" \
        --with-enginesdir="$LIBP11_PREFIX/engines-3" \
        --disable-static \
        --with-pkcs11-module= \
        CC="gcc${M32:+ $M32}" \
        CFLAGS="-O2" \
        OPENSSL_CFLAGS="-I$OPENSSL_PREFIX/include" \
        OPENSSL_LIBS="-L$OPENSSL_LIBDIR -lcrypto"
    make -j"$NCPU"
    make install
)
PKCS11PROV="$LIBP11_PREFIX/ossl-modules/pkcs11prov.so"
if [[ ! -f "$PKCS11PROV" ]]; then
    echo "❌ Error: libp11 build did not produce $PKCS11PROV" >&2
    exit 2
fi

# ── Stage the bundle's lib/ directory ─────────────────────────────────────────
# Stripped here, before patchelf; bundle-osslsigncode.sh does not strip Linux bundles.
STAGE_LIB="$TMP_DIR/stage-lib"
mkdir -p "$STAGE_LIB/ossl-modules"
cp -L "$OPENSSL_LIBDIR/libcrypto.so.3" "$OPENSSL_LIBDIR/libssl.so.3" "$STAGE_LIB/"
cp -L "$PKCS11PROV" "$STAGE_LIB/ossl-modules/pkcs11prov.so"
chmod 644 "$STAGE_LIB"/*.so.3 "$STAGE_LIB/ossl-modules/pkcs11prov.so"
strip --strip-unneeded "$STAGE_LIB"/*.so.3 "$STAGE_LIB/ossl-modules/pkcs11prov.so"
# libssl -> libcrypto next to it; pkcs11prov -> libcrypto one level up.
patchelf --set-rpath '$ORIGIN' "$STAGE_LIB/libssl.so.3"
patchelf --set-rpath '$ORIGIN/..' "$STAGE_LIB/ossl-modules/pkcs11prov.so"
# Licenses of the bundled libraries (OpenSSL: Apache-2.0, libp11: LGPL-2.1+).
cp "$TMP_DIR/openssl-$OPENSSL_VER/LICENSE.txt" "$STAGE_LIB/LICENSE.openssl.txt"
cp "$TMP_DIR/libp11-$LIBP11_VER/COPYING" "$STAGE_LIB/LICENSE.libp11.txt"

# ── osslsigncode ──────────────────────────────────────────────────────────────
git clone --depth 1 --branch "$OSSLSIGNCODE_VER" https://github.com/mtrojnar/osslsigncode.git "$TMP_DIR/osslsigncode"
# Point CMake only at the bundled OpenSSL. CMake's own RPATHs are skipped (osslsigncode sets
# INSTALL_RPATH_USE_LINK_PATH, which would add the build-time OpenSSL dir); the binary gets
# its final RUNPATH after stripping.
cmake -S "$TMP_DIR/osslsigncode" -B "$TMP_DIR/osslsigncode/build" \
    -DCMAKE_BUILD_TYPE=Release \
    "${CMAKE_ARCH_FLAGS[@]}" \
    -DOPENSSL_ROOT_DIR="$OPENSSL_PREFIX" \
    -DOPENSSL_USE_STATIC_LIBS=OFF \
    -DCMAKE_SKIP_RPATH=ON
make -C "$TMP_DIR/osslsigncode/build" -j"$NCPU"
OSSLSIGNCODE_BIN="$TMP_DIR/osslsigncode/build/osslsigncode"
strip --strip-unneeded "$OSSLSIGNCODE_BIN"
patchelf --set-rpath '$ORIGIN/../lib' "$OSSLSIGNCODE_BIN"

bash "$ASSETS_DIR/verify-linux-linkage.sh" --lib-dir "$STAGE_LIB" --max-glibc "$MAX_GLIBC" \
    "$OSSLSIGNCODE_BIN" "$STAGE_LIB"/*.so.3 "$STAGE_LIB/ossl-modules/pkcs11prov.so"

# ── Bundle ────────────────────────────────────────────────────────────────────
mkdir -p "$OUTPUT_DIR"
bash "$ASSETS_DIR/bundle-osslsigncode.sh" \
    --src "$OSSLSIGNCODE_BIN" \
    --lib-dir "$STAGE_LIB" \
    --output-dir "$OUTPUT_DIR" \
    --platform-arch "$PLATFORM_ARCH"

# Check the zip itself: the 1.3.x bundles were built fine but zipped without their libraries.
ZIP="$OUTPUT_DIR/win-codesign-linux-$PLATFORM_ARCH.zip"
CHECK_DIR="$TMP_DIR/zip-check"
mkdir -p "$CHECK_DIR"
unzip -q "$ZIP" -d "$CHECK_DIR"
for f in libcrypto.so.3 libssl.so.3 ossl-modules/pkcs11prov.so; do
    [[ -f "$CHECK_DIR/lib/$f" ]] || { echo "❌ $ZIP is missing lib/$f" >&2; exit 3; }
done
bash "$ASSETS_DIR/verify-linux-linkage.sh" --lib-dir "$CHECK_DIR/lib" --max-glibc "$MAX_GLIBC" \
    "$CHECK_DIR/bin/osslsigncode" "$CHECK_DIR"/lib/*.so.3 "$CHECK_DIR/lib/ossl-modules/pkcs11prov.so"
"$CHECK_DIR/bin/osslsigncode" --version
echo "✅ $ZIP"
