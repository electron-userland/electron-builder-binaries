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
NSIS_VERSION=${NSIS_VERSION:-3.12}
NSIS_BRANCH=${NSIS_BRANCH_OR_COMMIT:-v312}

OUTPUT_ARCHIVE="$OUT_DIR/nsis-bundle-linux-$NSIS_BRANCH.tar.gz"

echo "🐧 Building native Linux makensis binaries (amd64, arm64)..."
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

if ! docker buildx version &> /dev/null; then
    echo "❌ Docker buildx is required but not available"
    exit 1
fi

# =============================================================================
# Cleanup Handler
# =============================================================================

BUILDX_BUILDER="nsis-linux-builder-$$"

cleanup() {
    echo ""
    echo "🧹 Cleaning up Docker resources..."
    docker buildx rm "$BUILDX_BUILDER" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# =============================================================================
# Create Dockerfile
# =============================================================================

echo "📝 Creating Dockerfile for Linux build..."

DOCKERFILE="$OUT_DIR/Dockerfile.linux"

cat > "$DOCKERFILE" <<'DOCKERFILE_END'
FROM ubuntu:22.04 AS builder

ARG NSIS_BRANCH
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
RUN git clone --branch ${NSIS_BRANCH} --depth=1 https://github.com/NSIS-Dev/nsis.git nsis

WORKDIR /build/nsis

# Build native Linux makensis
# Skip stubs, plugins, utils - we only need the compiler
RUN scons \
    SKIPSTUBS=all \
    SKIPPLUGINS=all \
    SKIPUTILS=all \
    SKIPMISC=all \
    NSIS_CONFIG_CONST_DATA_PATH=no \
    NSIS_CONFIG_LOG=no \
    NSIS_MAX_STRLEN=8192 \
    PREFIX=/build/install \
    install-compiler

RUN chmod +x /build/install/makensis

# Export stage: scratch image contains only the binary so `type=local` output
# is the binary alone rather than the full Ubuntu filesystem (~400 MB).
FROM scratch
COPY --from=builder /build/install/makensis /output/makensis
DOCKERFILE_END

# =============================================================================
# Build Docker Images (multi-platform)
# =============================================================================

echo ""
echo "🔨 Building Docker images for amd64 and arm64 (this may take 10-20 minutes on first run)..."

TEMP_DIR="$OUT_DIR/temp-linux"
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR/docker-out"
mkdir -p "$TEMP_DIR/nsis-bundle/linux/x64"
mkdir -p "$TEMP_DIR/nsis-bundle/linux/arm64"

docker buildx create --name "$BUILDX_BUILDER" --use

docker buildx build \
    --platform "linux/amd64,linux/arm64" \
    --build-arg NSIS_BRANCH="$NSIS_BRANCH" \
    --output "type=local,dest=${TEMP_DIR}/docker-out" \
    -f "$DOCKERFILE" \
    "$OUT_DIR"

echo "  ✓ Docker images built successfully"

# =============================================================================
# Extract Compiled Binaries
# =============================================================================

echo ""
echo "📦 Extracting compiled Linux binaries..."

cp "$TEMP_DIR/docker-out/linux_amd64/output/makensis" "$TEMP_DIR/nsis-bundle/linux/x64/makensis"
cp "$TEMP_DIR/docker-out/linux_arm64/output/makensis" "$TEMP_DIR/nsis-bundle/linux/arm64/makensis"
chmod +x "$TEMP_DIR/nsis-bundle/linux/x64/makensis" "$TEMP_DIR/nsis-bundle/linux/arm64/makensis"
rm -rf "$TEMP_DIR/docker-out"

echo "  → Verifying binaries..."
for arch_dir in x64 arm64; do
    bin="$TEMP_DIR/nsis-bundle/linux/$arch_dir/makensis"
    if [ ! -f "$bin" ]; then
        echo "  ❌ Binary not found: $bin"
        exit 1
    fi
    if file "$bin" | grep -q "ELF"; then
        echo "  ✓ Valid Linux ELF binary ($arch_dir)"
    else
        echo "  ❌ Binary verification failed for $arch_dir: not a valid ELF"
        exit 1
    fi
done

# =============================================================================
# Create Version Metadata
# =============================================================================

echo ""
echo "📝 Creating version metadata..."

cat > "$TEMP_DIR/nsis-bundle/linux/VERSION.txt" <<EOF
Platform: Linux
Binary: makensis (native ELF binary)
Architectures: x64, arm64
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
  ./linux/x64/makensis your-script.nsi   # x86_64
  ./linux/arm64/makensis your-script.nsi # aarch64
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
