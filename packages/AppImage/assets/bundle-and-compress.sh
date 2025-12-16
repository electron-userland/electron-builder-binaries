#!/usr/bin/env bash
set -euo pipefail

# Root of the project (can be overridden by caller)
ROOT=$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)
OUT_DIR="${OUT_DIR:-$ROOT/out}"

mkdir -p "$OUT_DIR"

# Input directory containing the zip files
SRC_DIR="${SRC_DIR:-$ROOT/out/dist}"

# ----------------------------
# Runtime → project root
# ----------------------------
RUNTIME_ZIP="$SRC_DIR"/appimage-runtime*.zip
if [[ -f $RUNTIME_ZIP ]]; then
  echo "Extracting runtime to project root"
  unzip -qo "$RUNTIME_ZIP" -d "$OUT_DIR"
fi

# ----------------------------
# macOS → darwin/<arch>
# ----------------------------
for zip in "$SRC_DIR"/appimage-tools-macos-*.zip; do
  [[ -e "$zip" ]] || continue

  arch="$(basename "$zip" .zip | sed 's/.*-macos-//')"
  dest="$OUT_DIR/darwin/$arch"

  echo "Extracting macOS ($arch) → $dest"
  rm -rf "$dest"
  mkdir -p "$dest"
  unzip -qo "$zip" -d "$dest"
done

# ----------------------------
# Linux (all architectures) → linux/<arch>
# ----------------------------
LINUX_ZIP="$SRC_DIR/appimage-tools-linux-all-architectures.zip"
if [[ -f "$LINUX_ZIP" ]]; then
  echo "Extracting Linux (all architectures)"

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  unzip -qo "$LINUX_ZIP" -d "$tmpdir"

  for dir in "$tmpdir"/*; do
    [[ -d "$dir" ]] || continue

    arch="$(basename "$dir")"
    dest="$OUT_DIR/linux/$arch"

    echo "  → $dest"
    rm -rf "$dest"
    mkdir -p "$dest"
    cp -a "$dir/." "$dest/"
  done
fi

ARCHIVE_NAME="appimage-tools-runtime-$APPIMAGE_TYPE2_RELEASE.zip"
echo "📦 Creating ZIP bundle: $ARCHIVE_NAME"
(
cd "$SRC_DIR"
zip -r -9 "$OUT_DIR/$ARCHIVE_NAME" .
)
echo "✅ Done!"
echo "Bundle at: $OUT_DIR/$ARCHIVE_NAME"