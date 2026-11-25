#!/bin/bash

set -eo pipefail

# renovate: datasource=github-tags depName=plougher/squashfs-tools
SQUASHFS_TOOLS_VERSION_TAG=${SQUASHFS_TOOLS_VERSION_TAG:-"4.7.5"}
# renovate: datasource=gitlab-tags depName=xdg/desktop-file-utils registryUrl=https://gitlab.freedesktop.org
DESKTOP_UTILS_DEPS_VERSION_TAG=${DESKTOP_UTILS_DEPS_VERSION_TAG:-"0.28"}
# renovate: datasource=github-releases depName=uclouvain/openjpeg extractVersion=^v(?<version>.+)$
OPENJPEG_VERSION=${OPENJPEG_VERSION:-"2.5.4"}

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
REPO_SCRIPTS="$ROOT/../../scripts"
VERIFY_LICENSES="$REPO_SCRIPTS/verify-licenses.sh"
# shellcheck source=SCRIPTDIR/collect-licenses.sh
source "$ROOT/assets/collect-licenses.sh"

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
    rm -rf "$TEMP_DIR" "$TEMP_DIR.staging" "$TMP_DOCKER_CONTEXT"
}
# shellcheck disable=SC2154 # errorCode is assigned inside the trap
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
    --build-context repo-scripts="$REPO_SCRIPTS" \
    -f           "$ROOT/assets/Dockerfile" \
    "$ROOT"

echo ""
echo "📦 Extracting all tarballs..."

# Extract every architecture's tarball on its own, check its licenses, then merge them into TEMP_DIR (the
# LICENSES/MANIFEST.tsv files are concatenated; shared license files must be identical)
STAGING_DIR="$TEMP_DIR.staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
tarballs=0
while IFS= read -r tarfile; do
    name=$(basename "$tarfile" .tar.gz)
    echo "  Extracting $name..."
    mkdir "$STAGING_DIR/$name"
    tar -xzf "$tarfile" -C "$STAGING_DIR/$name"
    bash "$VERIFY_LICENSES" "$STAGING_DIR/$name"
    lic_merge "$TEMP_DIR" "$STAGING_DIR/$name"
    rm -f "$tarfile"
    tarballs=$((tarballs + 1))
done < <(find "${TMP_DOCKER_CONTEXT}" -name "*.tar.gz" -type f | sort)
rm -rf "$STAGING_DIR"
if [ "$tarballs" -ne 4 ]; then
    echo "❌ Expected 4 Linux tarballs (amd64, arm64, armv7, 386), found $tarballs"
    exit 1
fi
bash "$VERIFY_LICENSES" "$TEMP_DIR"


echo "✅ All builds completed and extracted"

# Verify executables have correct permissions
echo "🔐 Verifying executable permissions..."
chmod +x $TEMP_DIR/linux/x64/mksquashfs \
    $TEMP_DIR/linux/x64/unsquashfs \
    $TEMP_DIR/linux/x64/desktop-file-validate \
    $TEMP_DIR/linux/x64/opj_decompress \
    $TEMP_DIR/linux/ia32/mksquashfs \
    $TEMP_DIR/linux/ia32/unsquashfs \
    $TEMP_DIR/linux/ia32/desktop-file-validate \
    $TEMP_DIR/linux/arm64/mksquashfs \
    $TEMP_DIR/linux/arm64/unsquashfs \
    $TEMP_DIR/linux/arm64/desktop-file-validate \
    $TEMP_DIR/linux/arm64/opj_decompress \
    $TEMP_DIR/linux/arm32/mksquashfs \
    $TEMP_DIR/linux/arm32/unsquashfs \
    $TEMP_DIR/linux/arm32/desktop-file-validate

echo "✅ Executable permissions set"

echo ""
echo "✨ Extraction complete!"
echo ""
echo "📂 Directory structure:"
tree "$TEMP_DIR" -L 4 2>/dev/null || find "$TEMP_DIR" -maxdepth 4 -type f

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