#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Linux NSIS Binary Builder (Docker-based)
# =============================================================================
# Compiles ONLY the native Linux makensis binary from source using Docker
# Does NOT download or merge with base bundle
# Output: Single zip with just the Linux binary
# =============================================================================

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
OUT_DIR="$BASE_DIR/out/nsis"

# Version configuration
NSIS_VERSION=${NSIS_VERSION:-3.11}
NSIS_BRANCH=${NSIS_BRANCH_OR_COMMIT:-v311}

# Docker configuration
IMAGE_NAME="nsis-linux-builder:${NSIS_BRANCH}"
CONTAINER_NAME="nsis-linux-build-$$"

OUTPUT_ARCHIVE="$OUT_DIR/nsis-bundle-linux-$NSIS_BRANCH.tar.gz"

echo "🐧 Building native Linux makensis binary..."
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

if ! command -v docker &> /dev/null; then
    echo "❌ Docker is required but not installed"
    echo "   Install Docker: https://docs.docker.com/get-docker/"
    exit 1
fi

# =============================================================================
# Cleanup Handler
# =============================================================================

cleanup() {
    echo ""
    echo "🧹 Cleaning up Docker resources..."
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# =============================================================================
# Create Dockerfile
# =============================================================================

echo "📝 Creating Dockerfile for Linux build..."

DOCKERFILE="$OUT_DIR/Dockerfile.linux"

cat > "$DOCKERFILE" <<'DOCKERFILE_END'
FROM ubuntu:22.04

ARG NSIS_BRANCH=v310
ARG DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    scons \
    zlib1g-dev \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Clone NSIS source
RUN git clone --branch ${NSIS_BRANCH} --depth=1 https://github.com/kichik/nsis.git nsis

WORKDIR /build/nsis

# Build native Linux makensis
# Skip stubs, plugins, utils - we only need the compiler
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

# The binary is now at /build/install/makensis
RUN chmod +x /build/install/makensis

# Create output directory
RUN mkdir -p /output && \
    cp /build/install/makensis /output/makensis
DOCKERFILE_END

# =============================================================================
# Build Docker Image
# =============================================================================

echo ""
echo "🔨 Building Docker image (this may take 5-10 minutes on first run)..."

docker build \
    --build-arg NSIS_BRANCH="$NSIS_BRANCH" \
    -t "$IMAGE_NAME" \
    -f "$DOCKERFILE" \
    "$OUT_DIR"

if [ $? -ne 0 ]; then
    echo "❌ Docker build failed"
    exit 1
fi

echo "  ✓ Docker image built successfully"

# =============================================================================
# Extract Compiled Binary
# =============================================================================

echo ""
echo "📦 Extracting compiled Linux binary..."

# Create container
docker create --name "$CONTAINER_NAME" "$IMAGE_NAME" /bin/true

# Create temp directory for extraction
TEMP_DIR="$OUT_DIR/temp-linux"
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR/nsis-bundle/linux"

# Copy binary from container
docker cp "$CONTAINER_NAME:/output/makensis" "$TEMP_DIR/nsis-bundle/linux/makensis"

if [ ! -f "$TEMP_DIR/nsis-bundle/linux/makensis" ]; then
    echo "❌ Failed to extract Linux binary"
    exit 1
fi

chmod +x "$TEMP_DIR/nsis-bundle/linux/makensis"
echo "  ✓ Linux binary extracted"

# Verify binary
echo "  → Verifying binary..."
if file "$TEMP_DIR/nsis-bundle/linux/makensis" | grep -q "ELF"; then
    echo "  ✓ Valid Linux ELF binary"
else
    echo "  ❌ Binary verification failed: not a valid Linux ELF binary"
    exit 1
fi

# =============================================================================
# Create Version Metadata
# =============================================================================

echo ""
echo "📝 Creating version metadata..."

cat > "$TEMP_DIR/nsis-bundle/linux/VERSION.txt" <<EOF
Platform: Linux
Binary: makensis (native ELF binary)
Architecture: x86_64
Build Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Compiled from source: NSIS $NSIS_BRANCH
Compiler: GCC (Ubuntu 22.04)
Build system: SCons
Docker image: ubuntu:22.04

This binary is compiled from source with:
- Static linking where possible
- NSIS_MAX_STRLEN=8192
- NSIS_CONFIG_CONST_DATA_PATH=no

Usage:
  export NSISDIR="\$(pwd)/share/nsis"
  ./linux/makensis your-script.nsi
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
echo "  ✅ Linux Build Complete!"
echo "================================================================"
echo "  📁 Archive: $OUTPUT_ARCHIVE"
echo "  📊 Size:    $(du -h "$OUTPUT_ARCHIVE" | cut -f1)"
echo "================================================================"
echo ""
