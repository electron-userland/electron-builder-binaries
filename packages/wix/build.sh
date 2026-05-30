#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
OUT_DIR="$SCRIPT_DIR/out/wix"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

WIX_VERSION="3.14.1"
WIX_TAG="wix3141rtm"
WIX_ZIP_URL="https://github.com/wixtoolset/wix3/releases/download/${WIX_TAG}/wix314-binaries.zip"
WIX_SHA256="6ac824e1642d6f7277d0ed7ea09411a508f6116ba6fae0aa5f2c7daa2ff43d31"
ARCHIVE_NAME="wix-${WIX_VERSION}.tar.gz"

mkdir -p "$OUT_DIR" "$BUILD_DIR/extract" "$BUILD_DIR/bundle"

echo "Downloading WiX ${WIX_VERSION}..."
curl -fsSL --retry 3 "$WIX_ZIP_URL" -o "$BUILD_DIR/wix.zip"

echo "Verifying checksum..."
echo "${WIX_SHA256}  $BUILD_DIR/wix.zip" | sha256sum -c -

echo "Extracting..."
unzip -q "$BUILD_DIR/wix.zip" -d "$BUILD_DIR/extract"

echo "Filtering runtime files (excluding sdk/ and doc/)..."
rsync -a --exclude='sdk/' --exclude='doc/' "$BUILD_DIR/extract/" "$BUILD_DIR/bundle/"

echo "Creating archive..."
(cd "$BUILD_DIR/bundle" && tar -czf "$OUT_DIR/$ARCHIVE_NAME" .)

echo "Done: $OUT_DIR/$ARCHIVE_NAME"
echo "Size: $(du -h "$OUT_DIR/$ARCHIVE_NAME" | cut -f1)"
