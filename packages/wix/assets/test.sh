#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PACKAGE_DIR="$SCRIPT_DIR/.."
OUT_DIR="$PACKAGE_DIR/out/wix"

WIX_VERSION="3.14.1"
ARCHIVE="$OUT_DIR/wix-${WIX_VERSION}.tar.gz"
TEST_DIR="$(mktemp -d)"
XVFB_PID=""
trap 'rm -rf "$TEST_DIR"; [ -n "$XVFB_PID" ] && kill "$XVFB_PID" 2>/dev/null || true' EXIT

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

# Detect wine binary — Ubuntu installs wine, macOS Homebrew installs wine
WINE_BIN=""
for candidate in wine wine64; do
  if command -v "$candidate" &>/dev/null; then
    WINE_BIN="$candidate"
    break
  fi
done

if [ -z "$WINE_BIN" ]; then
  echo "SKIP: no wine binary found — skipping functional test"
  echo ""
  echo "=== Structural checks passed ==="
  exit 0
fi
echo "Using wine binary: $(command -v "$WINE_BIN") ($("$WINE_BIN" --version 2>/dev/null || echo unknown))"

# Wine prefix strategy:
#   Docker  → reuse the pre-initialized global prefix from the image build
#             (Mono is already installed; no runtime stall)
#   macOS   → fresh temp prefix per run (Homebrew wine handles Mono automatically)
if [ -f /.dockerenv ] && [ -d /root/.wine ]; then
  export WINEPREFIX=/root/.wine
  echo "Using pre-built Wine prefix: $WINEPREFIX"
else
  export WINEPREFIX="$TEST_DIR/.wine"
  export WINEDEBUG=-all
  # Start Xvfb for Wine's GUI subsystem if available (prevents display-related hangs)
  if command -v Xvfb &>/dev/null; then
    Xvfb :99 -screen 0 1024x768x24 -nolisten tcp &
    XVFB_PID=$!
    export DISPLAY=:99
    sleep 0.3
  fi
  echo "Initializing Wine prefix..."
  "$WINE_BIN" wineboot --init 2>/dev/null || true
  echo "PASS: Wine prefix initialized"
fi

cp "$SCRIPT_DIR/test.wxs" "$TEST_DIR/test.wxs"

# Convert Unix absolute paths to Wine Windows paths (Z: maps to /).
# Avoids calling winepath, which spawns another Wine process and can deadlock.
unix_to_wine() { echo "Z:$(echo "$1" | tr '/' '\\')"; }

WIN_WXS=$(unix_to_wine "$TEST_DIR/test.wxs")
WIN_WIXOBJ=$(unix_to_wine "$TEST_DIR/test.wixobj")
WIN_MSI=$(unix_to_wine "$TEST_DIR/test.msi")

# Sanity-check that basic Wine works before attempting .NET
echo "Running wine sanity check..."
if ! timeout 15 "$WINE_BIN" cmd.exe /c exit 2>/dev/null; then
  echo "SKIP: basic wine cmd.exe failed — likely running under CPU emulation (Rosetta/QEMU)"
  echo "      The Docker smoke test requires a native x86_64 host (e.g. GitHub Actions)."
  echo ""
  echo "=== Structural checks passed; functional test skipped (emulated host) ==="
  exit 0
fi
echo "PASS: wine sanity check"

echo "Running candle.exe..."
timeout 60 "$WINE_BIN" "$TEST_DIR/candle.exe" -nologo "$WIN_WXS" -o "$WIN_WIXOBJ" 2>/dev/null
if [ ! -f "$TEST_DIR/test.wixobj" ]; then
  echo "FAIL: candle.exe did not produce test.wixobj"
  exit 1
fi
echo "PASS: candle.exe compiled test.wxs → test.wixobj"

echo "Running light.exe..."
timeout 60 "$WINE_BIN" "$TEST_DIR/light.exe" -nologo -sval "$WIN_WIXOBJ" -o "$WIN_MSI" 2>/dev/null
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
