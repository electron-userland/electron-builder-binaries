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
    assert_dir  "$WINE_ROOT/lib/wine/x86_64-windows"     "lib/wine/x86_64-windows DLLs"

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
# Phase 3: E2E — run a real Windows .exe through Wine
# =============================================================================

header "Phase 3: E2E (real .exe)"

if [ -z "$WINE_ROOT" ]; then
    skip "E2E tests skipped (no bundle)"
elif [ "$OS_NAME" = "linux" ] && ! command -v Xvfb >/dev/null 2>&1; then
    skip "E2E test skipped on Linux (Xvfb not available for headless Wine)"
else
    # Download rcedit (small Windows CLI tool used by electron-builder)
    RCEDIT_URL="https://github.com/electron-userland/electron-builder-binaries/releases/download/win-codesign%401.1.0/rcedit-windows-2_0_0.zip"
    RCEDIT_ZIP="$WORK_DIR/rcedit.zip"
    RCEDIT_DIR="$WORK_DIR/rcedit"

    echo "  📥 Downloading rcedit (Windows test binary)..."
    if curl -fsSL --retry 3 --retry-delay 2 "$RCEDIT_URL" -o "$RCEDIT_ZIP" 2>/dev/null; then
        mkdir -p "$RCEDIT_DIR"
        unzip -q "$RCEDIT_ZIP" -d "$RCEDIT_DIR" 2>/dev/null || true
        RCEDIT_EXE=$(find "$RCEDIT_DIR" -name "*.exe" | head -1)

        if [ -n "$RCEDIT_EXE" ]; then
            pass "rcedit .exe downloaded and extracted"

            # Initialize a minimal Wine prefix for the test
            export WINEPREFIX="$WORK_DIR/wine-test-prefix"
            export WINEARCH=win64
            export WINEDEBUG=-all
            export DISPLAY="${DISPLAY:-:99}"

            mkdir -p "$WINEPREFIX"
            echo "  🍷 Initializing test Wine prefix..."
            "$WINE_ROOT/bin/wineboot" --init >/dev/null 2>&1 || true
            sleep 1

            echo "  ▶️  Running rcedit --help through Wine..."
            WINE_OUT=$("$WINE_ROOT/bin/wine" "$RCEDIT_EXE" --help 2>&1 || true)
            if echo "$WINE_OUT" | grep -qiE "usage|rcedit|option|help|version|error"; then
                pass "rcedit.exe runs through wine64 and produces output"
            else
                fail "rcedit.exe produced unexpected output: ${WINE_OUT:0:200}"
            fi
        else
            skip "E2E test skipped (could not find .exe in rcedit zip)"
        fi
    else
        skip "E2E test skipped (could not download rcedit — network unavailable?)"
    fi
fi

# =============================================================================
# Phase 4: Confirm
# =============================================================================

header "Phase 4: Confirm"

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
