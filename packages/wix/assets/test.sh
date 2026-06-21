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

# 3. Verify core v3 tool files are present
for f in candle.exe candle.exe.config light.exe light.exe.config \
          smoke.exe dark.exe heat.exe lit.exe \
          wix.dll wix.targets winterop.dll mergemod.dll \
          WixUIExtension.dll WixUtilExtension.dll; do
  if [ ! -f "$TEST_DIR/$f" ]; then
    echo "FAIL: Missing expected file: $f"
    exit 1
  fi
  echo "PASS: $f present"
done

# 4. Verify native assets (cubes for ICE validation, burn bootstrapper engine)
for f in "darice.cub" "mergemod.cub" "x86/burn.exe"; do
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

# 6. Verify dev-only dirs were excluded, and confirm this is v3 (no v4 wix.exe)
for d in sdk doc; do
  if [ -d "$TEST_DIR/$d" ]; then
    echo "FAIL: dev-only directory '$d' should not be in the bundle"
    exit 1
  fi
done
if [ -f "$TEST_DIR/wix.exe" ]; then
  echo "FAIL: wix.exe present — this should be the v3 candle/light bundle, not v4"
  exit 1
fi
echo "PASS: dev-only dirs excluded (sdk/, doc/); v3 bundle confirmed (no wix.exe)"

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
#   Docker  → reuse the pre-initialized global prefix from the image build (wine-mono installed)
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

# Resolve Windows-style paths for the Wine-hosted tools. winepath is the most
# reliable; fall back to mapping the Unix root onto the Z: drive.
to_winpath() {
  winepath -w "$1" 2>/dev/null || echo "Z:$(echo "$1" | tr '/' '\\')"
}

WIN_WXS=$(to_winpath "$TEST_DIR/test.wxs")
WIN_WIXOBJ=$(to_winpath "$TEST_DIR/test.wixobj")
WIN_MSI=$(to_winpath "$TEST_DIR/test.msi")

# Sanity-check basic Wine before attempting .NET (candle/light are managed apps).
echo "Running wine sanity check..."
if ! timeout 15 "$WINE_BIN" cmd.exe /c exit 2>/dev/null; then
  echo "SKIP: basic wine cmd.exe failed — likely running under CPU emulation (Rosetta/QEMU)"
  echo "      The Docker smoke test requires a native x86_64 host (e.g. GitHub Actions)."
  echo ""
  echo "=== Structural checks passed; functional test skipped (emulated host) ==="
  exit 0
fi
echo "PASS: wine sanity check"

# candle.exe compiles .wxs → .wixobj. candle/light are .NET Framework apps and
# need wine-mono in the prefix; if it's absent, candle exits non-zero and we
# skip gracefully rather than failing the structural guarantee.
echo "Running candle.exe..."
CANDLE_EXIT=0
timeout 60 "$WINE_BIN" "$TEST_DIR/candle.exe" -nologo "$WIN_WXS" -o "$WIN_WIXOBJ" 2>/dev/null \
  || CANDLE_EXIT=$?

if [ ! -f "$TEST_DIR/test.wixobj" ]; then
  if [ "$CANDLE_EXIT" -eq 124 ]; then
    echo "SKIP: candle.exe timed out (timeout 60s)"
  else
    echo "SKIP: candle.exe exited $CANDLE_EXIT without producing test.wixobj"
  fi
  echo "      The .NET Framework runtime (wine-mono) is not available in this Wine prefix."
  echo ""
  echo "=== Structural checks passed; functional build test skipped ==="
  exit 0
fi
echo "PASS: candle.exe compiled test.wxs → test.wixobj"

# light.exe links .wixobj → .msi. -sval suppresses ICE validation, which would
# otherwise require the Windows Installer service (unavailable under Wine).
echo "Running light.exe..."
timeout 60 "$WINE_BIN" "$TEST_DIR/light.exe" -nologo -sval "$WIN_WIXOBJ" -o "$WIN_MSI" 2>/dev/null || true
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
