#!/bin/bash

set -eo pipefail

SQUASHFS_TOOLS_VERSION_TAG=${SQUASHFS_TOOLS_VERSION_TAG:-"4.6.1"}
DESKTOP_UTILS_DEPS_VERSION_TAG=${DESKTOP_UTILS_DEPS_VERSION_TAG:-"0.28"}
OPENJPEG_VERSION=${OPENJPEG_VERSION:-"2.5.4"}

ROOT=$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)

# Check if buildx is available
if ! docker buildx version &> /dev/null; then
    echo "❌ Error: Docker buildx is not available"
    echo "Please install Docker buildx or use Docker Desktop which includes it"
    exit 1
fi

DEST="${DEST:-$ROOT/out/build}"
TMP_DOCKER_CONTEXT="/tmp/appimage-docker-context"
TEMP_DIR="/tmp/appimage-build-linux"

cleanup() {
    docker buildx rm appimage-builder || true
    echo "Cleaning up temporary directories..."
    rm -rf "$TEMP_DIR" "$TMP_DOCKER_CONTEXT"
}
trap 'errorCode=$?; echo "Error $errorCode at command: $BASH_COMMAND"; cleanup; exit $errorCode' ERR

echo "🏗️  Preparing build environment..."
cleanup
mkdir -p "$TEMP_DIR" "$TMP_DOCKER_CONTEXT"

# Create a new builder instance if it doesn't exist
echo "🏗️  Creating buildx builder instance..."
docker buildx create --name appimage-builder
docker buildx use appimage-builder

# Build all Linux architectures
echo ""
echo "🚀 Building for amd64, arm64, armv7, i386 platforms..."
docker buildx build \
    --platform   "linux/amd64,linux/arm64,linux/arm/v7,linux/386" \
    --build-arg  DESKTOP_UTILS_DEPS_VERSION_TAG="$DESKTOP_UTILS_DEPS_VERSION_TAG" \
    --build-arg  SQUASHFS_TOOLS_VERSION_TAG="$SQUASHFS_TOOLS_VERSION_TAG" \
    --build-arg  OPENJPEG_VERSION="$OPENJPEG_VERSION" \
    --cache-from type=local,src=.buildx-cache \
    --cache-to   type=local,dest=.buildx-cache,mode=max \
    --output     type=local,dest="${TMP_DOCKER_CONTEXT}" \
    -f           "$ROOT/assets/Dockerfile" \
    $ROOT

echo ""
echo "📦 Extracting all tarballs..."

# Find and extract all .tar.gz files to TMP_DIR root
find "${TMP_DOCKER_CONTEXT}" -name "*.tar.gz" -type f | while read -r tarfile; do
    echo "  Extracting $(basename "$tarfile")..."
    tar -xzf "$tarfile" -C "${TEMP_DIR}"
    rm -f "$tarfile"
done


echo "✅ All builds completed and extracted"

# Verify executables have correct permissions
echo "🔐 Verifying executable permissions..."
chmod +x $TEMP_DIR/linux/x64/mksquashfs \
    $TEMP_DIR/linux/x64/desktop-file-validate \
    $TEMP_DIR/linux/x64/opj_decompress \
    $TEMP_DIR/linux/ia32/mksquashfs \
    $TEMP_DIR/linux/ia32/desktop-file-validate \
    $TEMP_DIR/linux/arm64/mksquashfs \
    $TEMP_DIR/linux/arm64/desktop-file-validate \
    $TEMP_DIR/linux/arm64/opj_decompress \
    $TEMP_DIR/linux/arm32/mksquashfs \
    $TEMP_DIR/linux/arm32/desktop-file-validate

echo "✅ Executable permissions set"

echo ""
echo "✨ Extraction complete!"
echo ""
echo "📂 Directory structure:"
tree $TEMP_DIR -L 4 2>/dev/null || find $TEMP_DIR -type f -maxdepth 4

echo ""
echo "Creating tar.gz archive of all builds..."
ARCHIVE_NAME="appimage-tools-linux-all-architectures.tar.gz"
(
    cd "$TEMP_DIR"
    tar czf "$DEST/$ARCHIVE_NAME" .
)
echo "✓ Archive created: $DEST/$ARCHIVE_NAME"

cleanup

echo ""
echo "🎉 Done!"