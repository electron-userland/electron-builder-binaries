#!/usr/bin/env bash
set -euo pipefail

# Configuration
OSSLSIGNCODE_VER="${OSSLSIGNCODE_VER:-2.9}"
CMAKE_VERSION="${CMAKE_VERSION:-3.28.3}"
BUILD_ARCH="${PLATFORM_ARCH:-x64}" # x64 or arm64

CWD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$CWD/out/win-codesign"
BUILD_DIR="$CWD/.build/osslsigncode-windows-${BUILD_ARCH}"

echo "=================================================="
echo "Building osslsigncode for Windows"
echo "  Architecture: ${BUILD_ARCH}"
echo "  Version:      ${OSSLSIGNCODE_VER}"
echo "  Output:       ${OUTPUT_DIR}"
echo "=================================================="

# Clean up and prepare directories
rm -rf "$BUILD_DIR" "$OUTPUT_DIR"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

# Check if we're on Windows (GitHub Actions windows-2025 runner)
# OSTYPE can be: msys, cygwin, or win32 depending on the shell
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
    echo "✓ Detected Windows environment (OSTYPE=$OSTYPE)"
    
    # Determine the correct package prefix based on architecture
    if [[ "$BUILD_ARCH" == "arm64" ]]; then
        PACMAN_PREFIX="mingw-w64-clang-aarch64"
        PATH_PREFIX="/clangarm64"
    else
        PACMAN_PREFIX="mingw-w64-x86_64"
        PATH_PREFIX="/mingw64"
    fi
    
    echo "📦 Installing packages for ${BUILD_ARCH}..."
    # Install MSYS2 packages if not already installed
    pacman -S --noconfirm --needed \
        ${PACMAN_PREFIX}-gcc \
        ${PACMAN_PREFIX}-cmake \
        ${PACMAN_PREFIX}-openssl \
        ${PACMAN_PREFIX}-curl \
        ${PACMAN_PREFIX}-libgsf \
        ${PACMAN_PREFIX}-zlib \
        ${PACMAN_PREFIX}-pkgconf \
        git \
        make \
        zip \
        unzip
    
    # Ensure the correct MinGW is in PATH
    export PATH="${PATH_PREFIX}/bin:$PATH"
    echo "PATH: $PATH"
    
else
    echo "❌ This script must run on Windows with MSYS2/MinGW/cygwin environment."
    exit 1
fi

# Clone osslsigncode
echo "📥 Cloning osslsigncode ${OSSLSIGNCODE_VER}..."
cd "$BUILD_DIR"
git clone --depth 1 --branch "${OSSLSIGNCODE_VER}" \
    https://github.com/mtrojnar/osslsigncode.git

# Build osslsigncode
echo "🔨 Building osslsigncode..."
cd osslsigncode
mkdir -p build
cd build

# Use Unix Makefiles generator for MSYS2 (works across all MSYS2 environments)
cmake .. \
    -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$OUTPUT_DIR/install"

make -j$(nproc)

echo "✅ Build completed successfully!"

# Create portable bundle
echo "📦 Creating portable bundle..."
BUNDLE_DIR="$OUTPUT_DIR/bundle-${BUILD_ARCH}"
mkdir -p "$BUNDLE_DIR/bin" "$BUNDLE_DIR/lib"

# Copy the main executable
cp osslsigncode.exe "$BUNDLE_DIR/bin/"

# Copy required DLLs
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

# Create version file
"$BUNDLE_DIR/bin/osslsigncode.exe" --version > "$BUNDLE_DIR/VERSION.txt" 2>&1 || true
echo "platform: Windows" >> "$BUNDLE_DIR/VERSION.txt"
echo "architecture: ${BUILD_ARCH}" >> "$BUNDLE_DIR/VERSION.txt"
echo "created_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "$BUNDLE_DIR/VERSION.txt"

# Create launcher script (optional, for convenience)
cat > "$BUNDLE_DIR/osslsigncode.bat" <<'EOF'
@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
"%SCRIPT_DIR%bin\osslsigncode.exe" %*
endlocal
EOF

# Create ZIP archive
echo "📦 Creating ZIP archive..."
FILE="$CWD/out/win-codesign/win-codesign-windows-${BUILD_ARCH}.zip"
rm -f "$FILE"
cd "$BUNDLE_DIR"
zip -r -9 $FILE .

echo ""
echo "✅ Build completed successfully!"
echo "📦 Bundle: $FILE"
echo ""
echo "Bundle contents:"
ls -lh "$BUNDLE_DIR/bin"

# Clean up build directory
rm -rf "$BUILD_DIR"