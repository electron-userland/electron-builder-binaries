#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="/tmp/win-codesign-build"
OUTPUT_DIR="$ROOT_DIR/out/win-codesign"
ARCH=${PLATFORM_ARCH:-$(uname -m)}

# Clean up and prepare output directory
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR" "$OUTPUT_DIR/osslsigncode"

# ----------------------------  
# Build osslsigncode for both architectures
# ----------------------------
rm -rf "$OUTPUT_DIR/osslsigncode/darwin"
mkdir -p "$OUTPUT_DIR/osslsigncode/darwin"

cd "$TMP_DIR"

# Fetch source
git clone --depth 1 --branch $OSSLSIGNCODE_VER  https://github.com/mtrojnar/osslsigncode.git

SOURCE_DIR="$TMP_DIR/osslsigncode"
cd "$SOURCE_DIR"

# Detect architecture
echo "Building osslsigncode for $ARCH"

INSTALL_SUBDIR="$TMP_DIR/osslsigncode-install/darwin/$ARCH"
rm -rf "$INSTALL_SUBDIR"
mkdir -p "$INSTALL_SUBDIR"

# OpenSSL (Homebrew)
OPENSSL_PREFIX=$(brew --prefix openssl@3 || true)
if [[ -z "$OPENSSL_PREFIX" ]]; then
    echo "❌ openssl@3 not found. Install with 'brew install openssl@3'"
    exit 1
fi
echo "Using OpenSSL at $OPENSSL_PREFIX"

export CFLAGS="-arch $ARCH"
export CXXFLAGS="-arch $ARCH"
export LDFLAGS="-L$OPENSSL_PREFIX/lib"
export CPPFLAGS="-I$OPENSSL_PREFIX/include"
export PKG_CONFIG_PATH="${PKG_CONFIG_PATH:-}:$OPENSSL_PREFIX/lib/pkgconfig"

# Build with CMake
mkdir -p "$SOURCE_DIR/build"
cd "$SOURCE_DIR/build"

cmake -DCMAKE_PREFIX_PATH="$OPENSSL_PREFIX" \
        -DOPENSSL_ROOT_DIR="$OPENSSL_PREFIX" \
        -DCMAKE_INSTALL_PREFIX="$INSTALL_SUBDIR" \
        .. -DCMAKE_BUILD_TYPE=Release
make -j"$(sysctl -n hw.ncpu)"
make install

OSSLSIGNCODE_BIN="$INSTALL_SUBDIR/bin/osslsigncode"
if [[ ! -x "$OSSLSIGNCODE_BIN" ]]; then
    echo "❌ Build failed: osslsigncode binary not found"
    exit 2
fi

OUT_DIR="$OUTPUT_DIR/osslsigncode/darwin"
OUT_BIN="$OUT_DIR/$ARCH"
mkdir -p "$OUT_BIN"
cp "$OSSLSIGNCODE_BIN" "$OUT_BIN/osslsigncode"
# Write version info
"$OUT_BIN/osslsigncode" --version > "$OUT_BIN/VERSION.txt"

# Patch osslsigncode binary and zip
bash "$ROOT_DIR/assets/bundle-osslsigncode.sh" "$OUT_BIN/osslsigncode" "$OUTPUT_DIR"

rm -rf "$TMP_DIR"