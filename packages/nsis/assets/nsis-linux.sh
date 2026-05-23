#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Linux NSIS Binary Builder (Docker buildx, multi-arch)
# =============================================================================
# Compiles native Linux makensis binaries for x64 and arm64 from source using
# Docker buildx multi-platform builds. Does NOT download or merge with base bundle.
# Output: Single tar.gz with linux/x64/makensis and linux/arm64/makensis
# =============================================================================

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
OUT_DIR="$BASE_DIR/out/nsis"

# Version configuration
NSIS_VERSION=${NSIS_VERSION:-3.12}
NSIS_BRANCH=${NSIS_BRANCH_OR_COMMIT:-v312}

BUILDER_NAME="nsis-linux-builder-$$"
OUTPUT_ARCHIVE="$OUT_DIR/nsis-bundle-linux-$NSIS_BRANCH.tar.gz"

echo "🐧 Building native Linux makensis binaries (x64 + arm64)..."
echo "   Version: $NSIS_VERSION"
echo "   Branch:  $NSIS_BRANCH"
echo ""

# =============================================================================
# Setup
# =============================================================================

mkdir -p "$OUT_DIR"

# =============================================================================
# Check Prerequisites
# =============================================================================

if ! docker buildx version &> /dev/null; then
    echo "❌ Docker buildx is required but not available"
    echo "   Install Docker with buildx support: https://docs.docker.com/build/buildx/"
    exit 1
fi

# =============================================================================
# Cleanup Handler
# =============================================================================

cleanup() {
    echo ""
    echo "🧹 Cleaning up Docker resources..."
    docker buildx rm "$BUILDER_NAME" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# =============================================================================
# Create Dockerfile
# =============================================================================

echo "📝 Creating Dockerfile for Linux multi-arch build..."

DOCKERFILE="$OUT_DIR/Dockerfile.linux"

cat > "$DOCKERFILE" <<'DOCKERFILE_END'
FROM ubuntu:22.04

ARG NSIS_BRANCH
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential \
    scons \
    zlib1g-dev \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

RUN git init nsis && \
    git -C nsis remote add origin https://github.com/NSIS-Dev/nsis.git && \
    git -C nsis fetch --depth=1 origin ${NSIS_BRANCH} && \
    git -C nsis checkout FETCH_HEAD

WORKDIR /build/nsis

RUN scons \
    SKIPSTUBS=all \
    SKIPPLUGINS=all \
    SKIPUTILS=all \
    SKIPMISC=all \
    NSIS_CONFIG_CONST_DATA_PATH=no \
    NSIS_CONFIG_LOG=yes \
    NSIS_MAX_STRLEN=8192 \
    PREFIX=/build/install \
    install-compiler

RUN chmod +x /build/install/makensis
RUN mkdir -p /output && cp /build/install/makensis /output/makensis
DOCKERFILE_END

# =============================================================================
# Create Buildx Builder
# =============================================================================

echo ""
echo "🔧 Creating buildx builder (docker-container driver for multi-arch)..."
docker buildx create --name "$BUILDER_NAME" --driver docker-container --use

# =============================================================================
# Build Multi-Platform Image
# =============================================================================

TEMP_DIR="$OUT_DIR/temp-linux"
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR/docker-out" \
         "$TEMP_DIR/nsis-bundle/linux/x64" \
         "$TEMP_DIR/nsis-bundle/linux/arm64"

echo ""
echo "🔨 Building Docker image for linux/amd64 and linux/arm64..."
echo "   (First run may take 10-15 minutes)"

docker buildx build \
    --platform "linux/amd64,linux/arm64" \
    --build-arg NSIS_BRANCH="$NSIS_BRANCH" \
    --output "type=local,dest=$TEMP_DIR/docker-out" \
    -f "$DOCKERFILE" \
    "$OUT_DIR"

echo "  ✓ Multi-platform build complete"

# =============================================================================
# Extract Binaries
# =============================================================================

echo ""
echo "📦 Extracting binaries..."

if [ ! -f "$TEMP_DIR/docker-out/linux_amd64/output/makensis" ]; then
    echo "❌ x64 binary not found at expected path"
    echo "   Expected: $TEMP_DIR/docker-out/linux_amd64/output/makensis"
    ls -la "$TEMP_DIR/docker-out/" 2>/dev/null || true
    exit 1
fi

if [ ! -f "$TEMP_DIR/docker-out/linux_arm64/output/makensis" ]; then
    echo "❌ arm64 binary not found at expected path"
    echo "   Expected: $TEMP_DIR/docker-out/linux_arm64/output/makensis"
    ls -la "$TEMP_DIR/docker-out/" 2>/dev/null || true
    exit 1
fi

cp "$TEMP_DIR/docker-out/linux_amd64/output/makensis" "$TEMP_DIR/nsis-bundle/linux/x64/makensis"
cp "$TEMP_DIR/docker-out/linux_arm64/output/makensis" "$TEMP_DIR/nsis-bundle/linux/arm64/makensis"
chmod +x "$TEMP_DIR/nsis-bundle/linux/x64/makensis" "$TEMP_DIR/nsis-bundle/linux/arm64/makensis"
rm -rf "$TEMP_DIR/docker-out"

echo "  ✓ x64 binary extracted"
echo "  ✓ arm64 binary extracted"

# =============================================================================
# Verify Binaries
# =============================================================================

echo ""
echo "🔍 Verifying binaries..."

for arch_dir in x64 arm64; do
    bin="$TEMP_DIR/nsis-bundle/linux/$arch_dir/makensis"
    if command -v file &> /dev/null; then
        if file "$bin" | grep -q "ELF"; then
            echo "  ✓ $arch_dir: valid ELF binary"
        else
            echo "  ❌ $arch_dir: not a valid ELF binary"
            file "$bin"
            exit 1
        fi
    else
        ELF_MAGIC=$(od -N 4 -A n -t x1 "$bin" 2>/dev/null | tr -d ' \n')
        if [ "$ELF_MAGIC" = "7f454c46" ]; then
            echo "  ✓ $arch_dir: valid ELF binary (magic bytes)"
        else
            echo "  ❌ $arch_dir: ELF magic check failed (got: '$ELF_MAGIC')"
            exit 1
        fi
    fi
done

# =============================================================================
# Create Version Metadata
# =============================================================================

echo ""
echo "📝 Creating version metadata..."

cat > "$TEMP_DIR/nsis-bundle/linux/VERSION.txt" <<EOF
Platform: Linux
Architectures: x64, arm64
Binary: makensis (native ELF binary)
Build Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Compiled from source: NSIS $NSIS_BRANCH
Compiler: GCC (Ubuntu 22.04)
Build system: SCons
Docker image: ubuntu:22.04

This binary is compiled from source with:
- NSIS_CONFIG_LOG=yes
- NSIS_MAX_STRLEN=8192
- NSIS_CONFIG_CONST_DATA_PATH=no

Usage:
  export NSISDIR="\$(pwd)/windows"
  ./linux/x64/makensis your-script.nsi   # x64
  ./linux/arm64/makensis your-script.nsi  # arm64
EOF

# =============================================================================
# Create Archive
# =============================================================================

echo ""
echo "📦 Creating Linux bundle archive..."

cd "$TEMP_DIR"
tar -czf "${OUTPUT_ARCHIVE}" nsis-bundle

# =============================================================================
# Cleanup
# =============================================================================

rm -f "$DOCKERFILE"
rm -rf "$TEMP_DIR"

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "================================================================"
echo "  ✅ Linux Build Complete (x64 + arm64)!"
echo "================================================================"
echo "  📁 Archive: $OUTPUT_ARCHIVE"
echo "  📊 Size:    $(du -h "$OUTPUT_ARCHIVE" | cut -f1)"
echo "================================================================"
echo ""
