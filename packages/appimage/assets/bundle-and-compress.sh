#!/usr/bin/env bash
set -exuo pipefail

# Root of the project (can be overridden by caller)
ROOT=$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
OUT_DIR="${OUT_DIR:-$ROOT/out}"

mkdir -p "$BUILD_DIR" "$OUT_DIR"

# Input directory containing the zip files
SRC_DIR="${SRC_DIR:-$ROOT/out/build}"

tree $SRC_DIR -L 5 2>/dev/null || find $SRC_DIR -maxdepth 5 -type f

# ----------------------------
# Runtime → project root
# ----------------------------
echo "Extracting runtime to project root"
unzip -qo "$SRC_DIR"/appimage-runtime*.zip -d "$BUILD_DIR"
rm -f "$SRC_DIR"/appimage-runtime*.zip

# ----------------------------
# macOS → darwin/<arch>
# ----------------------------
for zip in "$SRC_DIR"/appimage-tools-macos-*.zip; do
    [[ -e "$zip" ]] || continue
    
    arch="$(basename "$zip" .zip | sed 's/.*-macos-//')"
    dest="$BUILD_DIR/darwin/$arch"
    
    echo "Extracting macOS ($arch) → $dest"
    rm -rf "$dest"
    mkdir -p "$dest"
    unzip -qo "$zip" -d "$dest"
    rm -f "$zip"
done

# ----------------------------
# Linux (all architectures) → linux/<arch>
# ----------------------------
LINUX_ZIP="$SRC_DIR/appimage-tools-linux-all-architectures.zip"
echo "Extracting Linux (all architectures)"
unzip -qo "$LINUX_ZIP" -d "$BUILD_DIR"
rm -f "$LINUX_ZIP"

ARCHIVE_NAME="appimage-tools-runtime-$APPIMAGE_TYPE2_RELEASE.zip"
echo "📦 Creating ZIP bundle: $ARCHIVE_NAME"
(
    cd "$BUILD_DIR"
    zip -r -9 "$OUT_DIR/$ARCHIVE_NAME" .
)
echo "✅ Done!"
echo "Bundle at: $OUT_DIR/$ARCHIVE_NAME"