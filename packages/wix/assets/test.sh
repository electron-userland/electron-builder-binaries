#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PACKAGE_DIR="$SCRIPT_DIR/.."
OUT_DIR="$PACKAGE_DIR/out/wix"

WIX_VERSION="3.14.1"
ARCHIVE="$OUT_DIR/wix-${WIX_VERSION}.tar.gz"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

echo "=== WiX Bundle Smoke Test ==="
echo ""

# 1. Verify archive exists
if [ ! -f "$ARCHIVE" ]; then
  echo "FAIL: Archive not found: $ARCHIVE"
  exit 1
fi
echo "PASS: Archive exists ($(du -h "$ARCHIVE" | cut -f1))"

# 2. Extract
tar -xzf "$ARCHIVE" -C "$TEST_DIR"

# 3. Verify expected files are present
for f in candle.exe light.exe smoke.exe wix.dll WixUIExtension.dll winterop.dll mergemod.dll darice.cub; do
  if [ ! -f "$TEST_DIR/$f" ]; then
    echo "FAIL: Missing expected file: $f"
    exit 1
  fi
  echo "PASS: $f present"
done

# 4. Verify sdk/ and doc/ were excluded
for d in sdk doc; do
  if [ -d "$TEST_DIR/$d" ]; then
    echo "FAIL: Dev-only directory '$d' should not be in bundle"
    exit 1
  fi
done
echo "PASS: dev-only dirs excluded (sdk/, doc/)"

echo ""
echo "=== Functional test via Wine ==="

if ! command -v wine &>/dev/null; then
  echo "SKIP: wine not found — skipping functional test"
  echo ""
  echo "=== Structural checks passed ==="
  exit 0
fi

cp "$SCRIPT_DIR/test.wxs" "$TEST_DIR/test.wxs"

WIN_WXS=$(winepath -w "$TEST_DIR/test.wxs" 2>/dev/null)
WIN_WIXOBJ=$(winepath -w "$TEST_DIR/test.wixobj" 2>/dev/null)
WIN_MSI=$(winepath -w "$TEST_DIR/test.msi" 2>/dev/null)

echo "Running candle.exe..."
wine "$TEST_DIR/candle.exe" -nologo "$WIN_WXS" -o "$WIN_WIXOBJ"
if [ ! -f "$TEST_DIR/test.wixobj" ]; then
  echo "FAIL: candle.exe did not produce test.wixobj"
  exit 1
fi
echo "PASS: candle.exe compiled test.wxs → test.wixobj"

echo "Running light.exe..."
wine "$TEST_DIR/light.exe" -nologo -sval "$WIN_WIXOBJ" -o "$WIN_MSI"
if [ ! -f "$TEST_DIR/test.msi" ]; then
  echo "FAIL: light.exe did not produce test.msi"
  exit 1
fi
echo "PASS: light.exe linked test.wixobj → test.msi"

# Verify MSI magic bytes (OLE compound document: D0 CF 11 E0)
MAGIC=$(xxd -l 4 -p "$TEST_DIR/test.msi")
if [ "$MAGIC" != "d0cf11e0" ]; then
  echo "FAIL: test.msi has unexpected magic bytes: $MAGIC (expected d0cf11e0)"
  exit 1
fi
echo "PASS: test.msi is a valid OLE compound document (MSI magic bytes confirmed)"

echo ""
echo "=== All checks passed ==="
