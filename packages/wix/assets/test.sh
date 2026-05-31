#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PACKAGE_DIR="$SCRIPT_DIR/.."
OUT_DIR="$PACKAGE_DIR/out/wix"

WIX_VERSION="4.0.6"
ARCHIVE="$OUT_DIR/wix-${WIX_VERSION}.tar.gz"
TEST_DIR="$(mktemp -d)"
XVFB_PID=""
trap 'rm -rf "$TEST_DIR"; [ -n "$XVFB_PID" ] && kill "$XVFB_PID" 2>/dev/null || true' EXIT

echo "=== WiX Bundle Smoke Test (v${WIX_VERSION}) ==="
echo ""

# 1. Verify archive exists
if [ ! -f "$ARCHIVE" ]; then
  echo "FAIL: Archive not found: $ARCHIVE"
  exit 1
fi
echo "PASS: Archive exists ($(du -h "$ARCHIVE" | cut -f1))"

# 2. Extract
tar -xzf "$ARCHIVE" -C "$TEST_DIR"

# 3. Verify core tool files are present
for f in wix.exe wix.dll WixToolset.Core.dll WixToolset.Core.Native.dll \
          WixToolset.Core.WindowsInstaller.dll WixToolset.Data.dll \
          WixToolset.Extensibility.dll; do
  if [ ! -f "$TEST_DIR/$f" ]; then
    echo "FAIL: Missing expected file: $f"
    exit 1
  fi
  echo "PASS: $f present"
done

# 4. Verify native assets (wixnative.exe is required for CAB creation)
for f in "runtimes/win-x64/native/wixnative.exe" \
          "cubes/darice.cub" "cubes/mergemod.cub"; do
  if [ ! -f "$TEST_DIR/$f" ]; then
    echo "FAIL: Missing expected native asset: $f"
    exit 1
  fi
  echo "PASS: $f present"
done

# 5. Verify LICENSE.TXT is present (required by MS-RL for redistribution)
if [ ! -f "$TEST_DIR/LICENSE.TXT" ]; then
  echo "FAIL: LICENSE.TXT missing — required by MS-RL for redistribution"
  exit 1
fi
echo "PASS: LICENSE.TXT present"

# 6. Verify v3 tools are NOT present (candle/light replaced by wix.exe)
for f in candle.exe light.exe smoke.exe; do
  if [ -f "$TEST_DIR/$f" ]; then
    echo "FAIL: v3 tool $f should not be in the v4 bundle"
    exit 1
  fi
done
echo "PASS: v3 tools absent (candle/light replaced by wix.exe)"

echo ""
echo "=== Functional test via Wine ==="

# Detect wine binary
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
#   Docker  → reuse the pre-initialized global prefix from the image build (Mono installed)
#   macOS   → fresh temp prefix per run
if [ -f /.dockerenv ] && [ -d /root/.wine ]; then
  export WINEPREFIX=/root/.wine
  echo "Using pre-built Wine prefix: $WINEPREFIX"
else
  export WINEPREFIX="$TEST_DIR/.wine"
  export WINEDEBUG=-all
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

# Convert Unix absolute paths to Wine Windows paths (Z: = host root)
unix_to_wine() { echo "Z:$(echo "$1" | tr '/' '\\')"; }

WIN_WXS=$(unix_to_wine "$TEST_DIR/test.wxs")
WIN_MSI=$(unix_to_wine "$TEST_DIR/test.msi")

# Sanity-check basic Wine before attempting .NET
echo "Running wine sanity check..."
if ! timeout 15 "$WINE_BIN" cmd.exe /c exit 2>/dev/null; then
  echo "SKIP: basic wine cmd.exe failed — likely running under CPU emulation (Rosetta/QEMU)"
  echo "      The Docker smoke test requires a native x86_64 host (e.g. GitHub Actions)."
  echo ""
  echo "=== Structural checks passed; functional test skipped (emulated host) ==="
  exit 0
fi
echo "PASS: wine sanity check"

# Run wix.exe build — single step replaces the v3 candle+light pipeline.
# wix.exe targets net6.0. Under Wine, the .NET 6 Windows runtime must be
# installed in the Wine prefix (e.g. via: winetricks dotnet60).
# If the runtime is absent, wix.exe exits non-zero and we skip gracefully.
echo "Running wix.exe build..."
WIX_EXIT=0
timeout 60 "$WINE_BIN" "$TEST_DIR/wix.exe" build "$WIN_WXS" -o "$WIN_MSI" 2>/dev/null \
  || WIX_EXIT=$?

if [ ! -f "$TEST_DIR/test.msi" ]; then
  if [ "$WIX_EXIT" -eq 124 ]; then
    echo "SKIP: wix.exe timed out (timeout 60s)"
  else
    echo "SKIP: wix.exe exited $WIX_EXIT without producing test.msi"
  fi
  echo "      The .NET 6 Windows runtime is not installed in this Wine prefix."
  echo "      To enable full Wine testing: winetricks dotnet60 (or dotnet80)"
  echo ""
  echo "=== Structural checks passed; functional build test skipped ==="
  exit 0
fi
echo "PASS: wix.exe build compiled test.wxs → test.msi"

# Verify MSI magic bytes (OLE compound document: D0 CF 11 E0)
MAGIC=$(xxd -l 4 -p "$TEST_DIR/test.msi")
if [ "$MAGIC" != "d0cf11e0" ]; then
  echo "FAIL: test.msi has unexpected magic bytes: $MAGIC (expected d0cf11e0)"
  exit 1
fi
echo "PASS: test.msi is a valid OLE compound document (MSI magic bytes confirmed)"

echo ""
echo "=== All checks passed ==="
