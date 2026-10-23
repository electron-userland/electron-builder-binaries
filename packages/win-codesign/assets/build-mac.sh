#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── CLI ───────────────────────────────────────────────────────────────────────

usage() {
    cat >&2 << EOF
Usage: $0 [options]
  --arch              Target architecture: arm64, x86_64
                      (default: \$PLATFORM_ARCH or native uname -m)
  --osslsigncode-ver  osslsigncode version tag to clone and build
                      (default: \$OSSLSIGNCODE_VER or '2.9')
  --openssl-ver       OpenSSL release to build and link statically
                      (default: \$OPENSSL_VER or '3.5.9'; set \$OPENSSL_SHA256 when overriding)
  --output-dir        Output directory for the ZIP artifact
                      (default: <package-root>/out/win-codesign)
  -h|--help           Show this help
EOF
    exit 1
}

ARCH="${PLATFORM_ARCH:-$(uname -m)}"
OSSLSIGNCODE_VER="${OSSLSIGNCODE_VER:-2.9}"
# OpenSSL 3.5 is the current LTS line (supported until 2030-04-08). The checksum
# matches the upstream release tarball (also pinned by Homebrew's openssl@3 formula).
OPENSSL_VER="${OPENSSL_VER:-3.5.9}"
OPENSSL_SHA256="${OPENSSL_SHA256:-603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a}"
# Self-contained binary, so it no longer inherits the build runner's macOS version.
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-11.0}"
OUTPUT_DIR="$SCRIPT_DIR/out/win-codesign"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)             ARCH="$2";             shift 2 ;;
        --osslsigncode-ver) OSSLSIGNCODE_VER="$2"; shift 2 ;;
        --openssl-ver)      OPENSSL_VER="$2";      shift 2 ;;
        --output-dir)       OUTPUT_DIR="$2";       shift 2 ;;
        -h|--help)          usage ;;
        *)                  echo "❌ Unknown argument: $1" >&2; usage ;;
    esac
done

TMP_DIR="$(mktemp -d /tmp/win-codesign-build-XXXXXX)"

# ── Cleanup on exit ───────────────────────────────────────────────────────────
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# ── Build ─────────────────────────────────────────────────────────────────────

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR" "$OUTPUT_DIR/osslsigncode"

rm -rf "$OUTPUT_DIR/osslsigncode/darwin"
mkdir -p "$OUTPUT_DIR/osslsigncode/darwin"

# Fetch source
git clone --depth 1 --branch "${OSSLSIGNCODE_VER}" https://github.com/mtrojnar/osslsigncode.git "$TMP_DIR/osslsigncode"

SOURCE_DIR="$TMP_DIR/osslsigncode"

echo "Building osslsigncode for $ARCH"

INSTALL_SUBDIR="$TMP_DIR/osslsigncode-install/darwin/$ARCH"
rm -rf "$INSTALL_SUBDIR"
mkdir -p "$INSTALL_SUBDIR"

# ── OpenSSL (static) ──────────────────────────────────────────────────────────
# Link OpenSSL statically so the bundle does not depend on Homebrew's openssl@3
# being installed at a matching version (the old dynamically-linked builds
# referenced /opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib and aborted in
# dyld when Homebrew moved openssl@3 from 3.6 to the 3.5 LTS line).
#   no-shared  only build libcrypto.a / libssl.a
#   no-module  compile the legacy provider into libcrypto, so `-pkcs12` files
#              using RC2/3DES still load without an ossl-modules directory
#   --openssldir=/private/etc/ssl  root-owned system location for openssl.cnf
#              (the Homebrew build used the user-writable Homebrew etc dir)
#   --prefix   only used for the compiled-in default MODULESDIR/ENGINESDIR,
#              so it must be a path regular users cannot create (not $TMP_DIR);
#              the libs are staged with DESTDIR and never installed there.
#              Users loading an external provider (e.g. pkcs11-provider) pass
#              `-provider <path>` or set OPENSSL_MODULES, as before.
case "$ARCH" in
    arm64|aarch64) OPENSSL_TARGET="darwin64-arm64-cc" ;;
    x86_64|amd64)  OPENSSL_TARGET="darwin64-x86_64-cc" ;;
    *) echo "❌ Error: unsupported arch for OpenSSL build: $ARCH" >&2; exit 1 ;;
esac

OPENSSL_TARBALL="$TMP_DIR/openssl-$OPENSSL_VER.tar.gz"
OPENSSL_RUNTIME_PREFIX="/opt/win-codesign-openssl"
OPENSSL_DESTDIR="$TMP_DIR/openssl-destdir"
OPENSSL_PREFIX="$OPENSSL_DESTDIR$OPENSSL_RUNTIME_PREFIX"
echo "Building static OpenSSL $OPENSSL_VER ($OPENSSL_TARGET, macOS >= $MACOSX_DEPLOYMENT_TARGET)"
curl -fsSL --retry 3 --retry-delay 2 \
    "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VER/openssl-$OPENSSL_VER.tar.gz" \
    -o "$OPENSSL_TARBALL"
echo "$OPENSSL_SHA256  $OPENSSL_TARBALL" | shasum -a 256 -c -
tar -xzf "$OPENSSL_TARBALL" -C "$TMP_DIR"

(
    cd "$TMP_DIR/openssl-$OPENSSL_VER"
    ./Configure "$OPENSSL_TARGET" \
        no-shared no-module no-tests no-docs no-apps \
        "-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" \
        --prefix="$OPENSSL_RUNTIME_PREFIX" \
        --openssldir=/private/etc/ssl \
        --libdir=lib
    make -j"$(sysctl -n hw.ncpu)" build_libs
    make install_dev DESTDIR="$OPENSSL_DESTDIR"
)

# ── osslsigncode ──────────────────────────────────────────────────────────────
mkdir -p "$SOURCE_DIR/build"

# Point CMake only at the static OpenSSL; never let FindOpenSSL fall back to Homebrew.
cmake -S "$SOURCE_DIR" -B "$SOURCE_DIR/build" \
    -DOPENSSL_ROOT_DIR="$OPENSSL_PREFIX" \
    -DOPENSSL_USE_STATIC_LIBS=TRUE \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
    -DCMAKE_FIND_FRAMEWORK=NEVER \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_SUBDIR" \
    -DCMAKE_BUILD_TYPE=Release

make -C "$SOURCE_DIR/build" -j"$(sysctl -n hw.ncpu)"
make -C "$SOURCE_DIR/build" install

OSSLSIGNCODE_BIN="$INSTALL_SUBDIR/bin/osslsigncode"
if [[ ! -x "$OSSLSIGNCODE_BIN" ]]; then
    echo "❌ Error: Build failed — osslsigncode binary not found at $OSSLSIGNCODE_BIN"
    exit 2
fi

# Fail the build if the binary references anything outside the OS (e.g. Homebrew dylibs).
bash "$SCRIPT_DIR/assets/verify-macos-linkage.sh" "$OSSLSIGNCODE_BIN"

OUT_DIR="$OUTPUT_DIR/osslsigncode/darwin"
OUT_BIN="$OUT_DIR/$ARCH"
mkdir -p "$OUT_BIN"
cp "$OSSLSIGNCODE_BIN" "$OUT_BIN/osslsigncode"
"$OUT_BIN/osslsigncode" --version > "$OUT_BIN/VERSION.txt"

bash "$SCRIPT_DIR/assets/bundle-osslsigncode.sh" \
    --src "$OUT_BIN/osslsigncode" \
    --output-dir "$OUTPUT_DIR" \
    --platform-arch "$ARCH"
