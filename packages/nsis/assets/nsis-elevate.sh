#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# elevate.exe Builder (Docker-based)
# =============================================================================
# Compiles elevate.exe 1.3.0 from source inside a Docker container.
# Does NOT download or merge with base bundle.
# Output: Single tar.gz with just elevate.exe at the bundle root.
#
# Mirrors the structure of nsis-linux.sh.
# Testable on macOS (Docker Desktop / Colima) and Linux.
# =============================================================================

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
OUT_DIR="$BASE_DIR/out/nsis"

# Version configuration
NSIS_BRANCH=${NSIS_BRANCH_OR_COMMIT:-v312}

# Elevate source
ELEVATE_VERSION="1.3.0"
ELEVATE_SHA256="b1b3f070353a0eadee2cea3a575049d10df9763ff24e39313da4cec9455382e1"

# Docker configuration
IMAGE_NAME="nsis-elevate-builder:${NSIS_BRANCH}"
CONTAINER_NAME="nsis-elevate-build-$$"

OUTPUT_ARCHIVE="$OUT_DIR/nsis-bundle-elevate-$NSIS_BRANCH.tar.gz"

echo "⬆️  Building elevate.exe from source (Docker)..."
echo "   elevate version: $ELEVATE_VERSION"
echo "   Branch:          $NSIS_BRANCH"
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

echo "📝 Creating Dockerfile for elevate.exe build..."

DOCKERFILE="$OUT_DIR/Dockerfile.elevate"

cat > "$DOCKERFILE" <<'DOCKERFILE_END'
FROM ubuntu:22.04

ARG ELEVATE_VERSION
ARG ELEVATE_SHA256
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    curl \
    p7zip-full \
    mingw-w64 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Download and SHA256-verify the source archive inside the container.
RUN curl -fsSL \
    "https://code.kliu.org/misc/elevate/elevate-${ELEVATE_VERSION}-redist.7z" \
    -o elevate-redist.7z && \
    echo "${ELEVATE_SHA256}  elevate-redist.7z" | sha256sum -c

# Extract only the src/ tree (preserves the libs/ subdirectory used by #include)
RUN 7z x elevate-redist.7z "src/" -y

# GCC on Linux does not normalise backslashes in #include paths;
# patch the one backslash path before compiling.
RUN sed 's|libs\\SimpleString.h|libs/SimpleString.h|' \
    src/elevate.c > src/elevate_patched.c

# Compile resource file (embeds UAC manifest + version info)
RUN i686-w64-mingw32-windres \
    --include-dir src -D NDEBUG -D _M_IX86 \
    src/elevate.rc -o src/elevate-res.o

# Compile 32-bit stripped console binary.
# -nostartfiles + -Wl,-e,_elevate mirrors MSVC's /entry:elevate.
# Safe because the source calls ExitProcess() at every exit path.
RUN mkdir -p /output && \
    i686-w64-mingw32-gcc \
        -DUNICODE -D_UNICODE -D_WIN32_WINNT=0x0600 \
        '-D__forceinline=__attribute__((always_inline))' \
        -O2 -s \
        -nostartfiles -Wl,-e,_elevate \
        -I src \
        -o /output/elevate.exe \
        src/elevate_patched.c src/elevate-res.o \
        -lkernel32 -lshell32 \
        -static-libgcc
DOCKERFILE_END

# =============================================================================
# Build Docker Image
# =============================================================================

echo ""
echo "🔨 Building Docker image..."

docker build \
    --build-arg ELEVATE_VERSION="$ELEVATE_VERSION" \
    --build-arg ELEVATE_SHA256="$ELEVATE_SHA256" \
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
echo "📦 Extracting compiled elevate.exe..."

docker create --name "$CONTAINER_NAME" "$IMAGE_NAME" /bin/true

TEMP_DIR="$OUT_DIR/temp-elevate"
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR/nsis-bundle"

docker cp "$CONTAINER_NAME:/output/elevate.exe" "$TEMP_DIR/nsis-bundle/elevate.exe"

if [ ! -f "$TEMP_DIR/nsis-bundle/elevate.exe" ]; then
    echo "❌ Failed to extract elevate.exe from container"
    exit 1
fi

echo "  ✓ elevate.exe extracted"

# =============================================================================
# Verify Binary (PE MZ header)
# =============================================================================

echo "  → Verifying binary..."

MZ=$(od -N 2 -A n -t x1 "$TEMP_DIR/nsis-bundle/elevate.exe" 2>/dev/null | tr -d ' \n')
if [ "$MZ" = "4d5a" ]; then
    echo "  ✓ Valid PE binary (MZ header)"
else
    echo "  ❌ Binary verification failed: not a valid PE (MZ header check failed)"
    exit 1
fi

# =============================================================================
# Create Archive
# =============================================================================

echo ""
echo "📦 Creating elevate bundle archive..."

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
echo "  ✅ elevate.exe Build Complete!"
echo "================================================================"
echo "  📁 Archive: $OUTPUT_ARCHIVE"
echo "  📊 Size:    $(du -h "$OUTPUT_ARCHIVE" | cut -f1)"
echo "================================================================"
echo ""
