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
  --openssl-ver       OpenSSL release to build and bundle
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
# libp11 provides the pkcs11prov OpenSSL provider used for `-pkcs11module` signing.
LIBP11_VER="${LIBP11_VER:-0.4.21}"
LIBP11_SHA256="${LIBP11_SHA256:-efdb523aef8613d447e6a2d38227d4b389866f4bcf4b503130acd7f759490847}"
# Self-contained bundle, so it no longer inherits the build runner's macOS version.
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

# ── OpenSSL (bundled) ─────────────────────────────────────────────────────────
# Build OpenSSL from source and ship its dylibs inside the bundle (loaded via
# @rpath), so the bundle no longer depends on Homebrew's openssl@3 being
# installed at a matching version. The old builds referenced
# /opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib and aborted in dyld once
# Homebrew moved openssl@3 from 3.6 to the 3.5 LTS line.
#
# OpenSSL is deliberately NOT linked statically: PKCS#11 signing
# (`-pkcs11module`, used by electron-builder) loads libp11's pkcs11prov
# provider, which needs to share one libcrypto with osslsigncode. A static
# osslsigncode plus an external provider means two libcrypto copies, and the
# process segfaults in OPENSSL_cleanup at exit after signing. So we also build
# pkcs11prov against this OpenSSL and ship it in lib/ossl-modules, which the
# launcher points OPENSSL_MODULES at.
#
#   no-module  compile the legacy provider into libcrypto, so `-pkcs12` files
#              using RC2/3DES still load without an ossl-modules entry
#   --openssldir=/private/etc/ssl  root-owned system location for openssl.cnf
#              (the Homebrew build used the user-writable Homebrew etc dir)
#   --prefix   only used for the compiled-in default MODULESDIR/ENGINESDIR,
#              so it must be a path regular users cannot create (not $TMP_DIR);
#              the libs are staged with DESTDIR and never installed there.
case "$ARCH" in
    arm64|aarch64) OPENSSL_TARGET="darwin64-arm64-cc" ;;
    x86_64|amd64)  OPENSSL_TARGET="darwin64-x86_64-cc" ;;
    *) echo "❌ Error: unsupported arch for OpenSSL build: $ARCH" >&2; exit 1 ;;
esac

NCPU="$(sysctl -n hw.ncpu)"

fetch_verified() {
    local url="$1" sha256="$2" out="$3"
    curl -fsSL --retry 3 --retry-delay 2 "$url" -o "$out"
    echo "$sha256  $out" | shasum -a 256 -c -
}

# Rewrite absolute references to the bundled OpenSSL dylibs to @rpath/<name>.
relink_openssl() {
    local file="$1" dep base
    while IFS= read -r dep; do
        base="$(basename "$dep")"
        case "$base" in
            libcrypto.3.dylib|libssl.3.dylib)
                [[ "$dep" == @rpath/* ]] || install_name_tool -change "$dep" "@rpath/$base" "$file"
                ;;
        esac
    done < <(otool -L "$file" | awk 'NR>1 {print $1}')
}

add_rpath_once() {
    local file="$1" rpath="$2"
    local existing
    existing="$(otool -l "$file" | awk '/cmd LC_RPATH/ {getline; getline; print $2}')"
    grep -qxF "$rpath" <<< "$existing" || install_name_tool -add_rpath "$rpath" "$file"
}

OPENSSL_TARBALL="$TMP_DIR/openssl-$OPENSSL_VER.tar.gz"
OPENSSL_RUNTIME_PREFIX="/opt/win-codesign-openssl"
OPENSSL_DESTDIR="$TMP_DIR/openssl-destdir"
OPENSSL_PREFIX="$OPENSSL_DESTDIR$OPENSSL_RUNTIME_PREFIX"
OPENSSL_LIBDIR="$OPENSSL_PREFIX/lib"
echo "Building OpenSSL $OPENSSL_VER ($OPENSSL_TARGET, macOS >= $MACOSX_DEPLOYMENT_TARGET)"
fetch_verified "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VER/openssl-$OPENSSL_VER.tar.gz" \
    "$OPENSSL_SHA256" "$OPENSSL_TARBALL"
tar -xzf "$OPENSSL_TARBALL" -C "$TMP_DIR"

(
    cd "$TMP_DIR/openssl-$OPENSSL_VER"
    ./Configure "$OPENSSL_TARGET" \
        shared no-module no-tests no-docs no-apps \
        "-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" \
        --prefix="$OPENSSL_RUNTIME_PREFIX" \
        --openssldir=/private/etc/ssl \
        --libdir=lib
    make -j"$NCPU" build_libs
    make install_dev DESTDIR="$OPENSSL_DESTDIR"
)

# Make the dylibs relocatable before anything links against them, so every
# consumer records @rpath/libcrypto.3.dylib. Drop the static archives so
# nothing can pick them up by accident.
rm -f "$OPENSSL_LIBDIR"/*.a
for lib in libcrypto.3.dylib libssl.3.dylib; do
    install_name_tool -id "@rpath/$lib" "$OPENSSL_LIBDIR/$lib"
    relink_openssl "$OPENSSL_LIBDIR/$lib"
done

# ── libp11 pkcs11prov provider ────────────────────────────────────────────────
LIBP11_TARBALL="$TMP_DIR/libp11-$LIBP11_VER.tar.gz"
LIBP11_PREFIX="$TMP_DIR/libp11-install"
echo "Building libp11 $LIBP11_VER pkcs11prov against the bundled OpenSSL"
fetch_verified "https://github.com/OpenSC/libp11/releases/download/libp11-$LIBP11_VER/libp11-$LIBP11_VER.tar.gz" \
    "$LIBP11_SHA256" "$LIBP11_TARBALL"
tar -xzf "$LIBP11_TARBALL" -C "$TMP_DIR"

# The empty --with-pkcs11-module keeps configure from baking the build host's p11-kit proxy
# (a Homebrew Cellar path on the runners) into pkcs11prov as its default PKCS#11 module.
(
    cd "$TMP_DIR/libp11-$LIBP11_VER"
    ./configure \
        --prefix="$LIBP11_PREFIX" \
        --with-modulesdir="$LIBP11_PREFIX/ossl-modules" \
        --with-enginesdir="$LIBP11_PREFIX/engines-3" \
        --disable-static \
        --with-pkcs11-module= \
        CFLAGS="-arch $ARCH -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET -O2" \
        LDFLAGS="-arch $ARCH -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" \
        OPENSSL_CFLAGS="-I$OPENSSL_PREFIX/include" \
        OPENSSL_LIBS="-L$OPENSSL_LIBDIR -lcrypto"
    make -j"$NCPU"
    make install
)

PKCS11PROV="$(find "$LIBP11_PREFIX/ossl-modules" -name 'pkcs11prov.*' \( -name '*.dylib' -o -name '*.so' \) -type f | head -n 1)"
if [[ -z "$PKCS11PROV" ]]; then
    echo "❌ Error: libp11 build did not produce pkcs11prov" >&2
    exit 2
fi

# ── Stage the bundle's lib/ directory ─────────────────────────────────────────
STAGE_LIB="$TMP_DIR/stage-lib"
mkdir -p "$STAGE_LIB/ossl-modules"
cp "$OPENSSL_LIBDIR/libcrypto.3.dylib" "$OPENSSL_LIBDIR/libssl.3.dylib" "$STAGE_LIB/"
# OpenSSL looks providers up as <name>.dylib on macOS.
cp "$PKCS11PROV" "$STAGE_LIB/ossl-modules/pkcs11prov.dylib"
chmod 644 "$STAGE_LIB"/*.dylib "$STAGE_LIB/ossl-modules/pkcs11prov.dylib"
relink_openssl "$STAGE_LIB/ossl-modules/pkcs11prov.dylib"
add_rpath_once "$STAGE_LIB/ossl-modules/pkcs11prov.dylib" "@loader_path/.."
# Licenses of the bundled libraries (OpenSSL: Apache-2.0, libp11: LGPL-2.1+).
cp "$TMP_DIR/openssl-$OPENSSL_VER/LICENSE.txt" "$STAGE_LIB/LICENSE.openssl.txt"
cp "$TMP_DIR/libp11-$LIBP11_VER/COPYING" "$STAGE_LIB/LICENSE.libp11.txt"

# ── osslsigncode ──────────────────────────────────────────────────────────────
mkdir -p "$SOURCE_DIR/build"

# Point CMake only at the bundled OpenSSL; never let FindOpenSSL fall back to Homebrew.
# The runtime search path is set explicitly below, so skip CMake's build-tree RPATHs.
cmake -S "$SOURCE_DIR" -B "$SOURCE_DIR/build" \
    -DOPENSSL_ROOT_DIR="$OPENSSL_PREFIX" \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
    -DCMAKE_FIND_FRAMEWORK=NEVER \
    -DCMAKE_SKIP_RPATH=ON \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_SUBDIR" \
    -DCMAKE_BUILD_TYPE=Release

make -C "$SOURCE_DIR/build" -j"$NCPU"
make -C "$SOURCE_DIR/build" install

OSSLSIGNCODE_BIN="$INSTALL_SUBDIR/bin/osslsigncode"
if [[ ! -x "$OSSLSIGNCODE_BIN" ]]; then
    echo "❌ Error: Build failed — osslsigncode binary not found at $OSSLSIGNCODE_BIN"
    exit 2
fi
relink_openssl "$OSSLSIGNCODE_BIN"
add_rpath_once "$OSSLSIGNCODE_BIN" "@executable_path/../lib"

# install_name_tool invalidates signatures; arm64 refuses to load unsigned code.
for f in "$OSSLSIGNCODE_BIN" "$STAGE_LIB"/*.dylib "$STAGE_LIB/ossl-modules/pkcs11prov.dylib"; do
    /usr/bin/codesign --force --sign - "$f"
done

# Fail the build if anything references a library outside macOS or the bundle (e.g. Homebrew dylibs),
# embeds a Homebrew path, or requires a newer macOS than the deployment target.
bash "$SCRIPT_DIR/assets/verify-macos-linkage.sh" --lib-dir "$STAGE_LIB" --macos-target "$MACOSX_DEPLOYMENT_TARGET" \
    "$OSSLSIGNCODE_BIN" "$STAGE_LIB"/*.dylib "$STAGE_LIB/ossl-modules/pkcs11prov.dylib"

OUT_DIR="$OUTPUT_DIR/osslsigncode/darwin"
OUT_BIN="$OUT_DIR/$ARCH"
mkdir -p "$OUT_BIN"
cp "$OSSLSIGNCODE_BIN" "$OUT_BIN/osslsigncode"
DYLD_LIBRARY_PATH="$STAGE_LIB" "$OUT_BIN/osslsigncode" --version > "$OUT_BIN/VERSION.txt"

bash "$SCRIPT_DIR/assets/bundle-osslsigncode.sh" \
    --src "$OUT_BIN/osslsigncode" \
    --lib-dir "$STAGE_LIB" \
    --output-dir "$OUTPUT_DIR" \
    --platform-arch "$ARCH"
