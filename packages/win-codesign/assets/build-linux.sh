#!/usr/bin/env bash
set -euo pipefail

# Configuration
PLATFORM_ARCH="${PLATFORM_ARCH:-amd64}"
OSSLSIGNCODE_VER="${OSSLSIGNCODE_VER:-2.9}"
CMAKE_VERSION="${CMAKE_VERSION:-3.28.3}"

# Normalize architecture names and map to Docker platforms
case "$PLATFORM_ARCH" in
  x86_64|amd64)
    PLATFORM_ARCH="amd64"
    DOCKER_PLATFORM="linux/amd64"
    ;;
  aarch64|arm64)
    PLATFORM_ARCH="arm64"
    DOCKER_PLATFORM="linux/arm64"
    ;;
  ia32|i386|i686)
    PLATFORM_ARCH="i386"
    # i386 will be built on amd64 using multilib (32-bit userspace doesn't exist for Ubuntu 20.04)
    DOCKER_PLATFORM="linux/amd64"
    ;;
  *)
    echo "Error: Unsupported architecture: $PLATFORM_ARCH"
    echo "Supported: amd64, arm64, i386"
    exit 1
    ;;
esac

CWD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$CWD/out/win-codesign"

# Clean up and prepare output directory
mkdir -p "$OUTPUT_DIR/$PLATFORM_ARCH"

cidFile="/tmp/osslsigncode-linux-container-$PLATFORM_ARCH-$$"

cleanup() {
    if [[ -f "$cidFile" ]]; then
        containerId=$(cat "$cidFile")
        echo "Stopping docker container $containerId."
        docker rm -f "$containerId" || true
        rm -f "$cidFile"
    fi
}

# Check if previous docker containers are still running
cleanup

# Trap errors and cleanup
trap 'errorCode=$?; echo "Error $errorCode at command: $BASH_COMMAND"; cleanup; exit $errorCode' ERR

# ----------------------------
# Build osslsigncode (Linux)
# ----------------------------
ARCHIVE_ARCH_SUFFIX=$(echo "${PLATFORM_ARCH}" | tr -d '/' | tr '[:upper:]' '[:lower:]')
DOCKER_TAG="osslsigncode-linux-builder:$ARCHIVE_ARCH_SUFFIX"
OUT_DIR="$OUTPUT_DIR/$PLATFORM_ARCH"

echo "=================================================="
echo "Building osslsigncode for Linux"
echo "  Architecture: ${PLATFORM_ARCH}"
echo "  Docker Platform: ${DOCKER_PLATFORM}"
echo "  Version:      ${OSSLSIGNCODE_VER}"
echo "  CMake:        ${CMAKE_VERSION}"
echo "  Output:       ${OUT_DIR}"
echo "=================================================="

# Ensure buildx is set up
# if ! docker buildx ls | grep -q osslsigncode-linux-builder; then
#     docker buildx create --use --name osslsigncode-linux-builder
# else
#     docker buildx use osslsigncode-linux-builder
# fi

# Build Docker image for the target platform
docker buildx build \
    --platform "$DOCKER_PLATFORM" \
    --build-arg PLATFORM_ARCH="$PLATFORM_ARCH" \
    --build-arg OSSLSIGNCODE_VER="$OSSLSIGNCODE_VER" \
    --build-arg CMAKE_VERSION="$CMAKE_VERSION" \
    -f "$CWD/assets/Dockerfile" \
    -t "$DOCKER_TAG" \
    --load \
    "$CWD"

# Run container and extract output
docker run --cidfile="$cidFile" "$DOCKER_TAG" tail -f /dev/null &
sleep 2

containerId=$(cat "$cidFile")

# Copy the built archive from container
mkdir -p "$OUT_DIR"
docker cp "$containerId":/out/linux/osslsigncode/win-codesign-linux-"$ARCHIVE_ARCH_SUFFIX".zip "$OUTPUT_DIR/"

OUTPUT_FILE="$OUTPUT_DIR/win-codesign-linux-$ARCHIVE_ARCH_SUFFIX.zip"

cleanup

echo ""
echo "✅ Build completed successfully!"
echo "📦 Bundle: $OUTPUT_FILE"
echo ""

if command -v unzip >/dev/null 2>&1; then
    echo "Extracting bundle for verification..."
    VERIFY_DIR="$OUT_DIR/extracted"
    rm -rf "$VERIFY_DIR"
    mkdir -p "$VERIFY_DIR"
    unzip -q "$OUTPUT_FILE" -d "$VERIFY_DIR"
    
    echo "Bundle contents:"
    ls -lh "$VERIFY_DIR"
    
    if [[ -f "$VERIFY_DIR/VERSION.txt" ]]; then
        echo ""
        echo "Version info:"
        cat "$VERIFY_DIR/VERSION.txt"
    fi
fi