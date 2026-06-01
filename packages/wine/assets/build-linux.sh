#!/usr/bin/env bash
set -euo pipefail

# Build Wine for Linux x86_64 using Docker on ARM64 macOS
# This script handles building Wine in a Docker container with the correct platform

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="${ROOT_DIR:-$SCRIPT_DIR/..}"
WINE_VERSION="${WINE_VERSION:-11.0}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/out}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed or not in PATH"
    log_info "Please install Docker Desktop for Mac from https://www.docker.com/products/docker-desktop"
    exit 1
fi

# Check if Docker daemon is running
if ! docker info &> /dev/null; then
    log_error "Docker daemon is not running"
    log_info "Please start Docker Desktop"
    exit 1
fi

# Detect host architecture
HOST_ARCH=$(uname -m)
log_info "Host architecture: $HOST_ARCH"

if [ "$HOST_ARCH" = "arm64" ]; then
    log_info "ARM64 Mac detected - will build x86_64 Linux Wine via Docker emulation"
else
    log_info "x86_64 Mac detected - will build natively in Docker"
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Build Docker image
IMAGE_NAME="wine-builder-linux"
log_info "Building Docker image: $IMAGE_NAME"

docker build \
--platform linux/amd64 \
-t "$IMAGE_NAME" \
-f "$SCRIPT_DIR/Dockerfile" \
"$SCRIPT_DIR"

if [ $? -ne 0 ]; then
    log_error "Failed to build Docker image"
    exit 1
fi

log_info "Docker image built successfully"

# Run the build in Docker
log_info "Starting Wine build for Linux (Wine $WINE_VERSION)..."
log_warn "This may take 30-60 minutes on ARM64 Mac due to emulation"

docker run \
    --platform linux/amd64 \
    --rm \
    -v "$OUTPUT_DIR:/output" \
    -e WINE_VERSION="$WINE_VERSION" \
    -e OS_TARGET=linux \
    -e OUT_DIR=/output \
    "$IMAGE_NAME"

if [ $? -ne 0 ]; then
    log_error "Wine build failed"
    exit 1
fi

log_info "Wine build completed successfully!"
log_info "Output location: $OUTPUT_DIR"

# List the built artifacts
ARTIFACT="$OUTPUT_DIR/wine-${WINE_VERSION}-linux-x86_64.tar.xz"
if [ -f "$ARTIFACT" ]; then
    log_info "Build artifact:"
    ls -lh "$ARTIFACT"
else
    log_warn "Expected output file not found: $ARTIFACT"
    log_info "Contents of output directory:"
    ls -lh "$OUTPUT_DIR" 2>/dev/null || echo "(empty)"
    exit 1
fi