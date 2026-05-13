#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# macOS NSIS Binary Builder
# =============================================================================
# Compiles ONLY the native macOS makensis binary from source
# Does NOT download or merge with base bundle
# Output: Single zip with just the macOS binary
# Must be run on macOS (no Docker cross-compilation for macOS)
# =============================================================================

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
OUT_DIR="$BASE_DIR/out/nsis"
BUILD_DIR="$OUT_DIR/build-mac"

# Version configuration
NSIS_VERSION=${NSIS_VERSION:-3.12}
NSIS_BRANCH=${NSIS_BRANCH_OR_COMMIT:-v312}

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
    x86_64) ARCH_NAME="x64" ;;
    arm64) ARCH_NAME="arm64" ;;
    *) ARCH_NAME="$ARCH" ;;
esac

OUTPUT_ARCHIVE="$OUT_DIR/nsis-bundle-mac-$ARCH_NAME-$NSIS_BRANCH.tar.gz"

echo "🍎 Building native macOS makensis binary..."
echo "   Version:      $NSIS_VERSION"
echo "   Branch:       $NSIS_BRANCH"
echo "   Architecture: $ARCH_NAME ($ARCH)"
echo ""

# =============================================================================
# Setup
# =============================================================================

mkdir -p "$OUT_DIR"

# =============================================================================
# Check Prerequisites
# =============================================================================

# Check if running on macOS
if [ "$(uname -s)" != "Darwin" ]; then
    echo "❌ This script must be run on macOS"
    exit 1
fi

# Check for Xcode Command Line Tools
if ! xcode-select -p &> /dev/null; then
    echo "❌ Xcode Command Line Tools not found"
    echo "   Install with: xcode-select --install"
    exit 1
fi

# Check for scons
if ! command -v scons &> /dev/null; then
    echo "📦 Installing scons..."
    if command -v brew &> /dev/null; then
        brew install scons
    else
        python3 -m pip install --user scons 2>/dev/null || {
            echo "❌ Failed to install scons"
            echo "   Install with: brew install scons"
            echo "   Or: pip3 install scons"
            exit 1
        }
    fi
fi

# =============================================================================
# Clone NSIS Source
# =============================================================================

echo "📥 Cloning NSIS source..."

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

if ! git clone --branch "$NSIS_BRANCH" --depth=1 \
    https://github.com/NSIS-Dev/nsis.git "$BUILD_DIR/nsis"; then
    echo "❌ Failed to clone NSIS repository"
    exit 1
fi

echo "  ✓ NSIS source cloned"

# =============================================================================
# Build macOS Binary
# =============================================================================

echo ""
echo "🔨 Compiling native macOS binary..."
echo "   This may take 5-10 minutes..."

cd "$BUILD_DIR/nsis"

# Build with SCons
if ! scons \
    SKIPSTUBS=all \
    SKIPPLUGINS=all \
    SKIPUTILS=all \
    SKIPMISC=all \
    NSIS_CONFIG_CONST_DATA_PATH=no \
    NSIS_CONFIG_LOG=yes \
    NSIS_MAX_STRLEN=8192 \
    PREFIX="$BUILD_DIR/install" \
    install-compiler; then
    echo "❌ Compilation failed"
    echo "   Check that Xcode Command Line Tools are properly installed"
    exit 1
fi

echo "  ✓ Compilation successful"

# =============================================================================
# Verify Binary
# =============================================================================

COMPILED_BINARY="$BUILD_DIR/install/makensis"

if [ ! -f "$COMPILED_BINARY" ]; then
    echo "❌ Compiled binary not found at expected location"
    exit 1
fi

chmod +x "$COMPILED_BINARY"

echo ""
echo "🧪 Verifying binary..."

# Check if it's a valid Mach-O binary
if file "$COMPILED_BINARY" | grep -q "Mach-O"; then
    echo "  ✓ Valid macOS Mach-O binary"
else
    echo "  ❌ Binary verification failed: not a valid macOS Mach-O binary"
    exit 1
fi

# =============================================================================
# Package Binary
# =============================================================================

echo ""
echo "📦 Packaging macOS binary..."

TEMP_DIR="$OUT_DIR/temp-mac"
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR/nsis-bundle/mac"

cp "$COMPILED_BINARY" "$TEMP_DIR/nsis-bundle/mac/makensis"
chmod +x "$TEMP_DIR/nsis-bundle/mac/makensis"

# =============================================================================
# Create Version Metadata
# =============================================================================

echo ""
echo "📝 Creating version metadata..."

cat > "$TEMP_DIR/nsis-bundle/mac/VERSION.txt" <<EOF
Platform: macOS
Binary: makensis (native Mach-O binary)
Architecture: $ARCH_NAME ($ARCH)
Build Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Compiled from source: NSIS $NSIS_BRANCH
Compiler: Clang $(clang --version 2>&1 | head -1)
Build system: SCons
macOS Version: $(sw_vers -productVersion)

This binary is compiled from source with:
- Native macOS compilation (no cross-compile)
- NSIS_MAX_STRLEN=8192
- NSIS_CONFIG_CONST_DATA_PATH=no

Usage:
  export NSISDIR="\$(pwd)/share/nsis"
  ./mac/makensis your-script.nsi
EOF

# =============================================================================
# Create Archive
# =============================================================================

echo ""
echo "📦 Creating macOS bundle archive..."

cd "$TEMP_DIR"
tar -czf "${OUTPUT_ARCHIVE}" nsis-bundle

# =============================================================================
# Cleanup
# =============================================================================

echo ""
echo "🧹 Cleaning up..."
rm -rf "$BUILD_DIR"
rm -rf "$TEMP_DIR"

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "================================================================"
echo "  ✅ macOS Build Complete!"
echo "================================================================"
echo "  📁 Archive: $OUTPUT_ARCHIVE"
echo "  📊 Size:    $(du -h "$OUTPUT_ARCHIVE" | cut -f1)"
echo "  🏗️  Arch:    $ARCH_NAME"
echo "================================================================"
echo ""
