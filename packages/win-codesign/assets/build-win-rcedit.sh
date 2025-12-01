#!/usr/bin/env bash
set -euo pipefail

CWD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$CWD/out"/win-codesign

RCEDIT_VERSION="${RCEDIT_VERSION:-2.0.0}"

mkdir -p "$OUTPUT_DIR/rcedit"

echo "📦 Creating rcedit bundle..."

RCEDIT_BUNDLE_DIR="$OUTPUT_DIR/rcedit"
RCEDIT_ZIP="$OUTPUT_DIR/rcedit-windows-${RCEDIT_VERSION//./_}.zip"

rm -rf "$RCEDIT_BUNDLE_DIR"
mkdir -p "$RCEDIT_BUNDLE_DIR"

curl -L "https://github.com/electron/rcedit/releases/download/v$RCEDIT_VERSION/rcedit-x64.exe" \
-o "$RCEDIT_BUNDLE_DIR/rcedit-x64.exe"
curl -L "https://github.com/electron/rcedit/releases/download/v$RCEDIT_VERSION/rcedit-x86.exe" \
-o "$RCEDIT_BUNDLE_DIR/rcedit-x86.exe"

# Create VERSION.txt
{
    echo "bundle: rcedit"
    echo "created_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo ""
    echo "rcedit version info:"
    echo "x64 -------------------"
    echo ""
    echo "$($RCEDIT_BUNDLE_DIR/rcedit-x64.exe "$RCEDIT_BUNDLE_DIR/rcedit-x64.exe" --get-version-string "FileVersion")"
    echo "x86 -------------------"
    echo ""
    echo "$($RCEDIT_BUNDLE_DIR/rcedit-x64.exe "$RCEDIT_BUNDLE_DIR/rcedit-x86.exe" --get-version-string "FileVersion")"
} > "$RCEDIT_BUNDLE_DIR/VERSION.txt"

echo "📦 Zipping rcedit bundle..."
cd "$RCEDIT_BUNDLE_DIR"
zip -r -9 "$RCEDIT_ZIP" .

echo "✅ Created bundle: $RCEDIT_ZIP"
echo ""
