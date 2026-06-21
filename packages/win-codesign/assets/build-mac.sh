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
  --output-dir        Output directory for the ZIP artifact
                      (default: <package-root>/out/win-codesign)
  -h|--help           Show this help
EOF
    exit 1
}

ARCH="${PLATFORM_ARCH:-$(uname -m)}"
OSSLSIGNCODE_VER="${OSSLSIGNCODE_VER:-2.9}"
OUTPUT_DIR="$SCRIPT_DIR/out/win-codesign"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)             ARCH="$2";             shift 2 ;;
        --osslsigncode-ver) OSSLSIGNCODE_VER="$2"; shift 2 ;;
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

# OpenSSL (Homebrew)
OPENSSL_PREFIX=$(brew --prefix openssl@3 || true)
if [[ -z "$OPENSSL_PREFIX" ]]; then
    echo "❌ Error: openssl@3 not found. Install with 'brew install openssl@3'"
    exit 1
fi
echo "Using OpenSSL at $OPENSSL_PREFIX"

export CFLAGS="-arch $ARCH"
export CXXFLAGS="-arch $ARCH"
export LDFLAGS="-L$OPENSSL_PREFIX/lib"
export CPPFLAGS="-I$OPENSSL_PREFIX/include"
export PKG_CONFIG_PATH="${PKG_CONFIG_PATH:-}:$OPENSSL_PREFIX/lib/pkgconfig"

mkdir -p "$SOURCE_DIR/build"

cmake -S "$SOURCE_DIR" -B "$SOURCE_DIR/build" \
    -DCMAKE_PREFIX_PATH="$OPENSSL_PREFIX" \
    -DOPENSSL_ROOT_DIR="$OPENSSL_PREFIX" \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_SUBDIR" \
    -DCMAKE_BUILD_TYPE=Release

make -C "$SOURCE_DIR/build" -j"$(sysctl -n hw.ncpu)"
make -C "$SOURCE_DIR/build" install

OSSLSIGNCODE_BIN="$INSTALL_SUBDIR/bin/osslsigncode"
if [[ ! -x "$OSSLSIGNCODE_BIN" ]]; then
    echo "❌ Error: Build failed — osslsigncode binary not found at $OSSLSIGNCODE_BIN"
    exit 2
fi

OUT_DIR="$OUTPUT_DIR/osslsigncode/darwin"
OUT_BIN="$OUT_DIR/$ARCH"
mkdir -p "$OUT_BIN"
cp "$OSSLSIGNCODE_BIN" "$OUT_BIN/osslsigncode"
"$OUT_BIN/osslsigncode" --version > "$OUT_BIN/VERSION.txt"

bash "$SCRIPT_DIR/assets/bundle-osslsigncode.sh" \
    --src "$OUT_BIN/osslsigncode" \
    --output-dir "$OUTPUT_DIR" \
    --platform-arch "$ARCH"
