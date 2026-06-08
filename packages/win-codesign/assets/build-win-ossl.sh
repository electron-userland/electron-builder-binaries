#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── CLI ───────────────────────────────────────────────────────────────────────

usage() {
    cat >&2 << EOF
Usage: $0 [options]
  --arch              Target architecture: x64, arm64
                      (default: \$PLATFORM_ARCH or 'x64')
  --osslsigncode-ver  osslsigncode version tag to clone and build
                      (default: \$OSSLSIGNCODE_VER or '2.9')
  --cmake-version     CMake version (informational; resolved via MSYS2 packages)
                      (default: \$CMAKE_VERSION or '3.28.3')
  --output-dir        Output directory for the ZIP artifact
                      (default: <package-root>/out/win-codesign)
  -h|--help           Show this help
EOF
    exit 1
}

BUILD_ARCH="${PLATFORM_ARCH:-x64}"
OSSLSIGNCODE_VER="${OSSLSIGNCODE_VER:-2.9}"
CMAKE_VERSION="${CMAKE_VERSION:-3.28.3}"
OUTPUT_DIR="$SCRIPT_DIR/out/win-codesign"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)             BUILD_ARCH="$2";       shift 2 ;;
        --osslsigncode-ver) OSSLSIGNCODE_VER="$2"; shift 2 ;;
        --cmake-version)    CMAKE_VERSION="$2";    shift 2 ;;
        --output-dir)       OUTPUT_DIR="$2";       shift 2 ;;
        -h|--help)          usage ;;
        *)                  echo "❌ Unknown argument: $1" >&2; usage ;;
    esac
done

BUILD_DIR="$SCRIPT_DIR/.build/osslsigncode-windows-${BUILD_ARCH}"

# ── Cleanup on exit ───────────────────────────────────────────────────────────
cleanup() {
    rm -rf "$BUILD_DIR"
}
trap cleanup EXIT

# ── Main ─────────────────────────────────────────────────────────────────────

echo "=================================================="
echo "Building osslsigncode for Windows"
echo "  Architecture: ${BUILD_ARCH}"
echo "  Version:      ${OSSLSIGNCODE_VER}"
echo "  Output:       ${OUTPUT_DIR}"
echo "=================================================="

rm -rf "$BUILD_DIR" "$OUTPUT_DIR"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

# Require MSYS2/MinGW/Cygwin — this script must run on Windows
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
    echo "✓ Detected Windows environment (OSTYPE=$OSTYPE)"

    if [[ "$BUILD_ARCH" == "arm64" ]]; then
        PACMAN_PREFIX="mingw-w64-clang-aarch64"
        PATH_PREFIX="/clangarm64"
    else
        PACMAN_PREFIX="mingw-w64-x86_64"
        PATH_PREFIX="/mingw64"
    fi

    echo "📦 Installing packages for ${BUILD_ARCH}..."
    pacman -S --noconfirm --needed \
        "${PACMAN_PREFIX}-gcc" \
        "${PACMAN_PREFIX}-cmake" \
        "${PACMAN_PREFIX}-openssl" \
        "${PACMAN_PREFIX}-curl" \
        "${PACMAN_PREFIX}-libgsf" \
        "${PACMAN_PREFIX}-zlib" \
        "${PACMAN_PREFIX}-pkgconf" \
        git \
        make \
        zip \
        unzip

    export PATH="${PATH_PREFIX}/bin:$PATH"
    echo "PATH: $PATH"
else
    echo "❌ Error: This script must run on Windows with an MSYS2/MinGW/Cygwin environment."
    exit 1
fi

echo "📥 Cloning osslsigncode ${OSSLSIGNCODE_VER}..."
git clone --depth 1 --branch "${OSSLSIGNCODE_VER}" \
    https://github.com/mtrojnar/osslsigncode.git \
    "$BUILD_DIR/osslsigncode"

echo "🔨 Building osslsigncode..."
cmake -S "$BUILD_DIR/osslsigncode" -B "$BUILD_DIR/osslsigncode/build" \
    -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$OUTPUT_DIR/install"

make -C "$BUILD_DIR/osslsigncode/build" -j"$(nproc)"

echo "✅ Build completed successfully!"

echo "📦 Creating portable bundle..."
BUNDLE_DIR="$OUTPUT_DIR/bundle-${BUILD_ARCH}"
mkdir -p "$BUNDLE_DIR/bin" "$BUNDLE_DIR/lib"

cp "$BUILD_DIR/osslsigncode/build/osslsigncode.exe" "$BUNDLE_DIR/bin/"

echo "🔍 Detecting required DLLs..."
if [[ "$BUILD_ARCH" == "arm64" ]]; then
    GREP_PATTERN="clangarm64"
else
    GREP_PATTERN="mingw64"
fi

REQUIRED_DLLS=$(ldd "$BUNDLE_DIR/bin/osslsigncode.exe" | \
    grep "$GREP_PATTERN" | \
    awk '{print $3}' | \
    sort -u)

for dll in $REQUIRED_DLLS; do
    if [[ -f "$dll" ]]; then
        echo "  ➕ $dll"
        cp "$dll" "$BUNDLE_DIR/bin/"
    fi
done

"$BUNDLE_DIR/bin/osslsigncode.exe" --version > "$BUNDLE_DIR/VERSION.txt" 2>&1 || true
{
    echo "platform: Windows"
    echo "architecture: ${BUILD_ARCH}"
    echo "created_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
} >> "$BUNDLE_DIR/VERSION.txt"

cat > "$BUNDLE_DIR/osslsigncode.bat" <<'EOF'
@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
"%SCRIPT_DIR%bin\osslsigncode.exe" %*
endlocal
EOF

echo "📦 Creating ZIP archive..."
ARCHIVE="$OUTPUT_DIR/win-codesign-windows-${BUILD_ARCH}.zip"
rm -f "$ARCHIVE"
cd "$BUNDLE_DIR"
zip -r -9 "$ARCHIVE" .

echo ""
echo "✅ Build completed successfully!"
echo "📦 Bundle: $ARCHIVE"
echo ""
echo "Bundle contents:"
ls -lh "$BUNDLE_DIR/bin"
