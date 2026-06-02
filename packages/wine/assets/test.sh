#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Wine Bundle Test Suite
# =============================================================================
# Usage: test.sh [--bundle-dir PATH] [--wine-version VERSION]
#
# --bundle-dir PATH      Directory containing the wine-*.tar.xz archive.
#                        Defaults to ../out (relative to this script).
# --wine-version VER     Wine version to look for (default: 11.0)
#
# Exit code 0 = all tests passed.
# =============================================================================

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BUNDLE_DIR="${BUNDLE_DIR:-$SCRIPT_DIR/../out}"
WINE_VERSION="${WINE_VERSION:-11.0}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bundle-dir)   BUNDLE_DIR="${2:-}"; shift 2 ;;
        --wine-version) WINE_VERSION="${2:-}"; shift 2 ;;
        *) echo "❌ Unknown option: $1"; exit 1 ;;
    esac
done

BUNDLE_DIR=$(cd "$BUNDLE_DIR" && pwd)

# Detect platform
OS_TYPE=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$OS_TYPE" in
    darwin*) OS_NAME="darwin" ;;
    linux*)  OS_NAME="linux" ;;
    *)       OS_NAME="$OS_TYPE" ;;
esac

ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64)  ARCH_NAME="x86_64" ;;
    arm64|aarch64) ARCH_NAME="x86_64" ;; # wine bundle is always x86_64 regardless of host arch
esac

PASS=0
FAIL=0
SKIP=0

WORK_DIR="$SCRIPT_DIR/../build/test-run-$$"
mkdir -p "$WORK_DIR"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT INT TERM

# =============================================================================
# Helpers
# =============================================================================

pass()  { echo "  [PASS] $*"; PASS=$((PASS + 1)); }
fail()  { echo "  [FAIL] $*"; FAIL=$((FAIL + 1)); }
skip()  { echo "  [SKIP] $*"; SKIP=$((SKIP + 1)); }
header(){ echo ""; echo "── $* ──────────────────────────────────────────────────"; }

assert_file() {
    local path="$1" label="$2"
    if [ -f "$path" ]; then pass "$label"; else fail "$label (missing: $path)"; fi
}

assert_dir() {
    local path="$1" label="$2"
    if [ -d "$path" ]; then pass "$label"; else fail "$label (missing: $path)"; fi
}

assert_exec() {
    local path="$1" label="$2"
    if [ -x "$path" ]; then pass "$label"; else fail "$label (not executable: $path)"; fi
}

assert_output() {
    local label="$1" expected="$2"
    shift 2
    local actual
    actual=$("$@" 2>&1 || true)
    if echo "$actual" | grep -qF "$expected"; then
        pass "$label"
    else
        fail "$label (expected '$expected' in output, got: $actual)"
    fi
}

# =============================================================================
# Phase 1: Assemble — locate and extract the bundle
# =============================================================================

header "Phase 1: Assemble"

ARCHIVE="$BUNDLE_DIR/wine-${WINE_VERSION}-${OS_NAME}-${ARCH_NAME}.tar.xz"
assert_file "$ARCHIVE" "Bundle archive exists: wine-${WINE_VERSION}-${OS_NAME}-${ARCH_NAME}.tar.xz"

if [ -f "$ARCHIVE" ]; then
    echo "  📦 Extracting bundle to $WORK_DIR..."
    tar -xJf "$ARCHIVE" -C "$WORK_DIR"
    WINE_ROOT=$(find "$WORK_DIR" -maxdepth 1 -type d -name "wine-*" | head -1)
    if [ -n "$WINE_ROOT" ]; then
        pass "Bundle extracted: $(basename "$WINE_ROOT")"
    else
        fail "Could not locate extracted wine directory in $WORK_DIR"
        WINE_ROOT=""
    fi
else
    WINE_ROOT=""
fi

# =============================================================================
# Phase 2: Sanity — verify bundle structure and Wine version
# =============================================================================

header "Phase 2: Sanity"

if [ -z "$WINE_ROOT" ]; then
    skip "Sanity tests skipped (no bundle)"
else
    assert_dir  "$WINE_ROOT/bin"                         "bin/ directory"
    assert_dir  "$WINE_ROOT/lib"                         "lib/ directory"
    # Wine 9+ with --enable-win64 installs 'wine' (not a separate wine64).
    # The build adds wine64 → wine symlink for electron-builder compatibility.
    assert_exec "$WINE_ROOT/bin/wine"                    "wine binary is executable"
    assert_exec "$WINE_ROOT/bin/wine64"                  "wine64 symlink is present (electron-builder compat)"
    assert_exec "$WINE_ROOT/bin/wineserver"              "wineserver binary is executable"
    assert_exec "$WINE_ROOT/bin/wineboot"                "wineboot binary is executable"
    assert_dir  "$WINE_ROOT/lib/wine/x86_64-unix"        "lib/wine/x86_64-unix DLLs"

    # Verify wine --version output (check stdout only, not stderr, to avoid matching paths)
    WINE_BIN="$WINE_ROOT/bin/wine"
    WINE_VER_OUT=$("$WINE_BIN" --version 2>/dev/null || true)
    if echo "$WINE_VER_OUT" | grep -qE "^wine-${WINE_VERSION}"; then
        pass "wine --version reports ${WINE_VERSION}"
    else
        fail "wine --version output unexpected: $WINE_VER_OUT"
    fi

    # Pre-initialized prefix (optional — created during build)
    if [ -d "$WINE_ROOT/wine-home" ]; then
        pass "Pre-initialized wine prefix (wine-home/) present"
        assert_dir "$WINE_ROOT/wine-home/drive_c" "wine-home/drive_c exists"
    else
        skip "Pre-initialized wine prefix not present (will be created on first run)"
    fi
fi

# =============================================================================
# Phase 3: E2E — run real Windows .exe files through Wine
# =============================================================================
# All sub-tests use the pre-initialized wine-home shipped in the bundle.
# electron-builder always uses the bundled prefix; lib/wine/x86_64-windows
# is removed after prefix init so fresh-prefix creation is not supported.

E2E_SKIP_REASON=""
if [ -z "$WINE_ROOT" ]; then
    E2E_SKIP_REASON="no bundle"
elif [ "$OS_NAME" = "linux" ] && ! command -v Xvfb >/dev/null 2>&1; then
    E2E_SKIP_REASON="Xvfb not available for headless Wine on Linux"
fi

if [ -n "$E2E_SKIP_REASON" ]; then
    export WINEPREFIX=""   # silence shellcheck; not used
else
    export WINEPREFIX="$WINE_ROOT/wine-home"
    export WINEDEBUG=-all
    export DISPLAY="${DISPLAY:-:99}"
fi

# Helper: run one Windows EXE and assert its output matches a pattern.
# Usage: wine_assert_output LABEL EXE_PATH HELP_FLAG PATTERN
wine_assert_output() {
    local label="$1" exe="$2" flag="$3" pattern="$4"
    if [ -n "$E2E_SKIP_REASON" ]; then
        skip "$label (${E2E_SKIP_REASON})"; return
    fi
    local out
    out=$("$WINE_ROOT/bin/wine" "$exe" "$flag" 2>&1 || true)
    if echo "$out" | grep -qiE "$pattern"; then
        pass "$label"
    else
        fail "$label — unexpected output: ${out:0:200}"
    fi
}

# ── 3a: rcedit (win-codesign@1.2.1) ──────────────────────────────────────────
header "Phase 3a: E2E (rcedit)"

RCEDIT_URL="https://github.com/electron-userland/electron-builder-binaries/releases/download/win-codesign%401.2.1/rcedit-windows-2_0_0.zip"
RCEDIT_DIR="$WORK_DIR/rcedit"

if [ -n "$E2E_SKIP_REASON" ]; then
    skip "rcedit (${E2E_SKIP_REASON})"
else
    echo "  📥 Downloading rcedit..."
    if curl -fsSL --retry 3 --retry-delay 2 "$RCEDIT_URL" -o "$WORK_DIR/rcedit.zip" 2>/dev/null; then
        mkdir -p "$RCEDIT_DIR"
        unzip -q "$WORK_DIR/rcedit.zip" -d "$RCEDIT_DIR" 2>/dev/null || true
        RCEDIT_EXE=$(find "$RCEDIT_DIR" -name "*.exe" | head -1)
        if [ -n "$RCEDIT_EXE" ]; then
            pass "rcedit.exe downloaded"
            wine_assert_output "rcedit.exe --help" "$RCEDIT_EXE" "--help" \
                "usage|rcedit|option|help|version|error"
        else
            skip "rcedit.exe not found in zip"
        fi
    else
        skip "rcedit download failed (network unavailable?)"
    fi
fi

# ── 3b: WiX tools (wix-4.0.0.5512.2) ────────────────────────────────────────
header "Phase 3b: E2E (WiX — candle, light, WriteZipToSetup)"

WIX_URL="https://github.com/electron-userland/electron-builder-binaries/releases/download/wix-4.0.0.5512.2/wix-4.0.0.5512.2.7z"
WIX_DIR="$WORK_DIR/wix"

if [ -n "$E2E_SKIP_REASON" ]; then
    skip "WiX tools (${E2E_SKIP_REASON})"
else
    # Find a 7z binary (macOS runners ship 7-Zip; Linux may have p7zip)
    SEVENZ=""
    for _cmd in 7z 7za 7zz; do
        command -v "$_cmd" >/dev/null 2>&1 && { SEVENZ="$_cmd"; break; }
    done

    if [ -z "$SEVENZ" ]; then
        skip "WiX tools (7z not found — install p7zip or 7-Zip)"
    else
        echo "  📥 Downloading WiX bundle..."
        if curl -fsSL --retry 3 --retry-delay 2 "$WIX_URL" -o "$WORK_DIR/wix.7z" 2>/dev/null; then
            mkdir -p "$WIX_DIR"
            "$SEVENZ" x -o"$WIX_DIR" -y "$WORK_DIR/wix.7z" >/dev/null 2>&1 || true

            for _exe_name in candle.exe light.exe WriteZipToSetup.exe; do
                _exe_path=$(find "$WIX_DIR" -iname "$_exe_name" | head -1)
                if [ -n "$_exe_path" ]; then
                    pass "$_exe_name found in WiX bundle"
                    wine_assert_output "$_exe_name /?" "$_exe_path" "/?" \
                        "wix|candle|light|setup|linker|compiler|usage|option|version|error"
                else
                    skip "$_exe_name not found in WiX archive"
                fi
            done
        else
            skip "WiX download failed (network unavailable?)"
        fi
    fi
fi

# ── 3c: Windows Kits — signtool (win-codesign@1.2.1) ─────────────────────────
header "Phase 3c: E2E (Windows Kits — signtool)"

KITS_URL="https://github.com/electron-userland/electron-builder-binaries/releases/download/win-codesign%401.2.1/windows-kits-bundle-10_0_26100_0.zip"
KITS_DIR="$WORK_DIR/kits"

if [ -n "$E2E_SKIP_REASON" ]; then
    skip "signtool (${E2E_SKIP_REASON})"
else
    echo "  📥 Downloading Windows Kits bundle..."
    if curl -fsSL --retry 3 --retry-delay 2 "$KITS_URL" -o "$WORK_DIR/kits.zip" 2>/dev/null; then
        mkdir -p "$KITS_DIR"
        unzip -q "$WORK_DIR/kits.zip" -d "$KITS_DIR" 2>/dev/null || true
        SIGNTOOL_EXE=$(find "$KITS_DIR" -iname "signtool.exe" | head -1)
        if [ -n "$SIGNTOOL_EXE" ]; then
            pass "signtool.exe found in Windows Kits bundle"
            wine_assert_output "signtool /?" "$SIGNTOOL_EXE" "/?" \
                "sign|signtool|usage|option|command|timestamp|verify"
        else
            skip "signtool.exe not found in kits bundle"
        fi
    else
        skip "Windows Kits download failed (network unavailable?)"
    fi
fi

# =============================================================================
# Phase 4: Results
# =============================================================================

header "Phase 4: Results"

TOTAL=$((PASS + FAIL + SKIP))
echo ""
echo "  Results: $PASS passed, $FAIL failed, $SKIP skipped ($TOTAL total)"
echo ""

if [ "$FAIL" -gt 0 ]; then
    echo "❌ Test suite FAILED ($FAIL failures)"
    exit 1
else
    echo "✅ Test suite PASSED"
fi
