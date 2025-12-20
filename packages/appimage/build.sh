#!/bin/bash

# Build script for AppImage tools for multiple platforms
# Compile for all builds possible if on MacOS w/ docker buildx.
# rm -rf out; TARGET=linux sh build.sh && TARGET=darwin sh build.sh && TARGET=runtime sh build.sh && TARGET=compress sh build.sh

set -e

echo "╔════════════════════════════════════════╗"
echo "║  🔧 AppImage Tools Build Script       ║"
echo "╚════════════════════════════════════════╝"
echo ""

# VERSIONS
export SQUASHFS_TOOLS_VERSION_TAG="4.6.1"
export APPIMAGE_TYPE2_RELEASE="20251108"

# Detect OS
ROOT=$(cd "$(dirname "$BASH_SOURCE")" && pwd)
TARGET=${TARGET:-$(uname | tr '[:upper:]' '[:lower:]')}

OUTPUT_DIR="$ROOT/out"
BUILD_DIR="$ROOT/build"
mkdir -p $BUILD_DIR $OUTPUT_DIR

if [ "$TARGET" = "darwin" ]; then
    echo "🍎 Detected macOS target - Building Darwin binaries..."
    DEST="$BUILD_DIR/darwin" bash $ROOT/assets/appimage-mac.sh    
elif [ "$TARGET" = "linux" ]; then
    echo "🐧 Detected Linux target - Building Linux binaries for all architectures..."
    DEST="$BUILD_DIR/linux" bash $ROOT/assets/appimage-linux.sh
elif [ "$TARGET" = "runtime" ]; then
    echo "📥 Downloading AppImage runtimes into bundle..."
    OUT_DIR="$OUTPUT_DIR" bash $ROOT/assets/download-runtime.sh --install-directory $BUILD_DIR/runtimes
elif [ "$TARGET" = "compress" ]; then
    echo "📦 Creating package hierarchy of all AppImage tools and runtimes..."
    OUT_DIR="$OUTPUT_DIR/appimage" BUILD_DIR="$BUILD_DIR" SRC_DIR="$OUTPUT_DIR" bash $ROOT/assets/bundle-and-compress.sh
else
    echo "❌ Unsupported TARGET: $TARGET"
    exit 1
fi

echo ""
echo "╔════════════════════════════════════════╗"
echo "║  ✅ Build Complete!                    ║"
echo "╚════════════════════════════════════════╝"
echo ""
echo "📂 Directory structure:"
tree $OUTPUT_DIR -L 3 2>/dev/null || find $OUTPUT_DIR -maxdepth 3 -type f


