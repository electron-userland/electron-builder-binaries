#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 7-Zip Bundle Test Suite
# =============================================================================
# Validates an extracted 7zip bundle directory.
#
# Usage:
#   bash test.sh --bundle-dir <path-to-extracted-bundle> [--platform PLATFORM]
#
# --bundle-dir PATH    Directory containing bin/, LICENSE.txt, COPYING
# --platform PLATFORM  linux | darwin | win  (auto-detected from OS if omitted)
#
# Exit code 0 = all tests passed.
# =============================================================================

BUNDLE_DIR=""
PLATFORM=""
STRUCTURAL_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bundle-dir)      BUNDLE_DIR="${2:-}"; shift 2 ;;
        --platform)        PLATFORM="${2:-}";   shift 2 ;;
        --structural-only) STRUCTURAL_ONLY=true; shift ;;
        --help|-h)
            echo "Usage: $0 --bundle-dir PATH [--platform linux|darwin|win] [--structural-only]"
            exit 0 ;;
        *) echo "❌ Unknown argument: $1"; exit 1 ;;
    esac
done

if [[ -z "$BUNDLE_DIR" ]]; then
    echo "Usage: $0 --bundle-dir <path-to-extracted-bundle> [--platform linux|darwin|win]"
    exit 1
fi

if [[ ! -d "${BUNDLE_DIR}/bin" ]]; then
    echo "❌ No bin/ directory found in ${BUNDLE_DIR}"
    exit 1
fi

# Auto-detect platform from OS if not provided
if [[ -z "$PLATFORM" ]]; then
    case "$(uname -s)" in
        Linux)                PLATFORM="linux"  ;;
        Darwin)               PLATFORM="darwin" ;;
        MINGW*|MSYS*|CYGWIN*) PLATFORM="win"    ;;
        *)                    PLATFORM="linux"  ;;
    esac
fi

# Determine current host OS for deciding whether execution tests are possible
CURRENT_OS="unknown"
case "$(uname -s)" in
    Linux)                CURRENT_OS="linux"  ;;
    Darwin)               CURRENT_OS="darwin" ;;
    MINGW*|MSYS*|CYGWIN*) CURRENT_OS="win"    ;;
esac

# Execution tests only make sense on the native platform.
# --structural-only suppresses them even on a matching host (e.g. linux-ia32 on x64).
CAN_EXECUTE=false
[[ "$PLATFORM" == "$CURRENT_OS" ]] && CAN_EXECUTE=true
$STRUCTURAL_ONLY && CAN_EXECUTE=false

# =============================================================================
# Workspace-local scratch dir (mirrors wine/test.sh pattern)
# =============================================================================

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORK_DIR="${SCRIPT_DIR}/../build/test-run-$$"
mkdir -p "$WORK_DIR"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT INT TERM

# =============================================================================
# Helpers
# =============================================================================

pass=0
fail=0
skip=0

ok()        { echo "  ✅ $1"; pass=$((pass + 1)); }
fail_test() { echo "  ❌ $1"; fail=$((fail + 1)); }
skip_test() { echo "  [SKIP] $1"; skip=$((skip + 1)); }

run_test() {
    local label="$1"; shift
    if "$@" > /dev/null 2>&1; then
        ok "$label"
    else
        fail_test "$label"
    fi
}

echo "🧪 Testing 7-Zip bundle at: ${BUNDLE_DIR} (platform: ${PLATFORM}, host: ${CURRENT_OS})"
echo ""

# =============================================================================
# Binary structure
# =============================================================================

echo "── Binary ───────────────────────────────────────────────────"

if [[ "$PLATFORM" == "win" ]]; then
    # Windows: upstream binary is 7za.exe; entrypoint wrapper is 7za.ps1
    EXE="7za.exe"
    BIN="${BUNDLE_DIR}/bin/${EXE}"

    if [[ -f "$BIN" ]]; then
        ok "${EXE} present"
    else
        fail_test "${EXE} missing at ${BIN}"
    fi

    if [[ -f "${BUNDLE_DIR}/bin/7za.ps1" ]]; then
        ok "7za.ps1 entrypoint present"
    else
        fail_test "7za.ps1 entrypoint missing"
    fi

    if grep -q '7za.exe' "${BUNDLE_DIR}/bin/7za.ps1" 2>/dev/null; then
        ok "7za.ps1 references 7za.exe"
    else
        fail_test "7za.ps1 does not reference 7za.exe"
    fi
else
    # Linux / macOS: upstream binary is 7zz; 7za is a symlink entrypoint
    BIN_REAL="${BUNDLE_DIR}/bin/7zz"
    BIN_LINK="${BUNDLE_DIR}/bin/7za"

    if [[ -f "$BIN_REAL" && -x "$BIN_REAL" ]]; then
        ok "7zz present and executable (upstream binary)"
    else
        fail_test "7zz missing or not executable at ${BIN_REAL}"
    fi

    if [[ -L "$BIN_LINK" ]]; then
        link_target="$(readlink "$BIN_LINK")"
        if [[ "$link_target" == "7zz" ]]; then
            ok "7za is a symlink → 7zz (entrypoint)"
        else
            fail_test "7za symlink points to '${link_target}' instead of '7zz'"
        fi
    else
        fail_test "7za entrypoint missing or not a symlink"
    fi

    # Use the entrypoint (symlink) for all functional tests
    EXE="7za"
    BIN="${BIN_LINK}"
fi

# =============================================================================
# Functional tests — skipped when cross-platform or --structural-only
# =============================================================================

echo ""
echo "── Functional ───────────────────────────────────────────────"

if ! $CAN_EXECUTE; then
    skip_test "${EXE} --help (cross-platform or structural-only)"
    skip_test "${EXE} identifies as 7-Zip"
    skip_test "creates a .7z archive"
    skip_test ".7z archive passes integrity test"
    skip_test "creates a .zip archive"
else
    run_test "${EXE} --help exits cleanly" "$BIN" --help

    if "$BIN" i > /dev/null 2>&1 || "$BIN" 2>/dev/null | head -1 | grep -qi "7-zip"; then
        ok "${EXE} identifies as 7-Zip"
    else
        fail_test "${EXE} did not identify as 7-Zip"
    fi

    echo "hello world" > "${WORK_DIR}/test.txt"

    if "$BIN" a -bd "${WORK_DIR}/test.7z" "${WORK_DIR}/test.txt" > /dev/null 2>&1; then
        ok "creates a .7z archive"
    else
        fail_test "failed to create .7z archive"
    fi

    if [[ -f "${WORK_DIR}/test.7z" ]]; then
        ok ".7z archive file exists"
        if "$BIN" t -bd "${WORK_DIR}/test.7z" > /dev/null 2>&1; then
            ok ".7z archive passes integrity test"
        else
            fail_test ".7z archive failed integrity test"
        fi
    fi

    if "$BIN" a -bd -tzip "${WORK_DIR}/test.zip" "${WORK_DIR}/test.txt" > /dev/null 2>&1; then
        ok "creates a .zip archive"
    else
        fail_test "failed to create .zip archive"
    fi
fi

# =============================================================================
# License files
# =============================================================================

echo ""
echo "── Legal ────────────────────────────────────────────────────"

if [[ -f "${BUNDLE_DIR}/LICENSE.txt" ]]; then
    ok "LICENSE.txt present"
    if grep -qi "LGPL\|Lesser General Public" "${BUNDLE_DIR}/LICENSE.txt"; then
        ok "LICENSE.txt contains LGPL text"
    else
        fail_test "LICENSE.txt does not mention LGPL"
    fi
else
    fail_test "LICENSE.txt missing"
fi

if [[ -f "${BUNDLE_DIR}/COPYING" ]]; then
    ok "COPYING present"
else
    fail_test "COPYING missing"
fi

# =============================================================================
# macOS: no non-system dylib references
# =============================================================================

if [[ "$PLATFORM" == "darwin" ]] && command -v otool > /dev/null 2>&1; then
    echo ""
    echo "── macOS dylib paths ────────────────────────────────────────"
    # Only consider indented lines (actual dylib entries); skip the binary-path
    # header lines that otool emits for each architecture slice of a universal binary.
    BAD="$(otool -L "$BIN_REAL" 2>/dev/null \
           | grep -E '^\s' \
           | awk '{print $1}' \
           | grep -Ev '^(/usr/lib|/System|@)' || true)"
    if [[ -z "$BAD" ]]; then
        ok "no non-system dylib references"
    else
        fail_test "non-system dylib references found: $BAD"
    fi
fi

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: ${pass} passed, ${fail} failed, ${skip} skipped"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[[ "$fail" -eq 0 ]] || exit 1
