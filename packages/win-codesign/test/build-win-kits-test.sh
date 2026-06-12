#!/usr/bin/env bash
# Unit + e2e tests for build-win-kits.sh helpers and full script flow.
# Run: bash packages/win-codesign/test/build-win-kits-test.sh
set -uo pipefail

PASS=0
FAIL=0
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../assets" && pwd)/build-win-kits.sh"

# ── Minimal assertion helpers ─────────────────────────────────────────────────

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        echo "  ✅ $desc"
        PASS=$(( PASS + 1 ))
    else
        echo "  ❌ $desc"
        echo "     expected: $(printf '%q' "$expected")"
        echo "     actual:   $(printf '%q' "$actual")"
        FAIL=$(( FAIL + 1 ))
    fi
}

assert_exit() {
    local desc="$1" expected_code="$2"
    shift 2
    local actual_code=0
    "$@" >/dev/null 2>&1 || actual_code=$?
    assert_eq "$desc" "$expected_code" "$actual_code"
}

assert_file_exists() {
    local desc="$1" path="$2"
    if [ -f "$path" ]; then
        echo "  ✅ $desc"
        PASS=$(( PASS + 1 ))
    else
        echo "  ❌ $desc (missing: $path)"
        FAIL=$(( FAIL + 1 ))
    fi
}

# ── Setup ─────────────────────────────────────────────────────────────────────

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# Source helpers only (main body is gated by BASH_SOURCE guard)
# shellcheck source=../assets/build-win-kits.sh
source "$SCRIPT"

# ── copy_arch_files ───────────────────────────────────────────────────────────

echo ""
echo "▶ copy_arch_files"

setup_src() {
    local base="$1" arch file
    for arch in x86 x64; do
        mkdir -p "$base/$arch"
        for file in foo.dll bar.exe; do
            echo "stub" > "$base/$arch/$file"
        done
    done
}

SRC="$TMPDIR_ROOT/sdk"
DEST="$TMPDIR_ROOT/bundle"
setup_src "$SRC"
mkdir -p "$DEST"

ARCHITECTURES=("x86" "x64")
MISSING_FILES=()
copy_arch_files "$SRC" "$DEST" "foo.dll" "bar.exe" >/dev/null

assert_file_exists "copies x86/foo.dll"  "$DEST/x86/foo.dll"
assert_file_exists "copies x86/bar.exe"  "$DEST/x86/bar.exe"
assert_file_exists "copies x64/foo.dll"  "$DEST/x64/foo.dll"
assert_file_exists "copies x64/bar.exe"  "$DEST/x64/bar.exe"
assert_eq          "no missing files"    "0" "${#MISSING_FILES[@]}"

# Missing file tracking (single arch to keep count predictable)
SRC2="$TMPDIR_ROOT/sdk2"
DEST2="$TMPDIR_ROOT/bundle2"
mkdir -p "$SRC2/x86"
echo "stub" > "$SRC2/x86/present.dll"
mkdir -p "$DEST2"

ARCHITECTURES=("x86")
MISSING_FILES=()
copy_arch_files "$SRC2" "$DEST2" "present.dll" "absent.dll" >/dev/null

assert_eq "tracks 1 missing file" "1" "${#MISSING_FILES[@]}"
assert_file_exists "still copies present file" "$DEST2/x86/present.dll"

# Empty file list
SRC3="$TMPDIR_ROOT/sdk3"
DEST3="$TMPDIR_ROOT/bundle3"
mkdir -p "$SRC3/x86"
mkdir -p "$DEST3"
MISSING_FILES=()
copy_arch_files "$SRC3" "$DEST3" >/dev/null
assert_eq "empty file list copies nothing" "0" "${#MISSING_FILES[@]}"

# ── report_missing ────────────────────────────────────────────────────────────

echo ""
echo "▶ report_missing"

exit_code=0
( MISSING_FILES=(); report_missing "file(s)" ) || exit_code=$?
assert_eq "does not exit when list is empty" "0" "$exit_code"

exit_code=0
( MISSING_FILES=("a.dll" "b.dll"); report_missing "file(s)" ) || exit_code=$?
assert_eq "exits 1 when list is non-empty" "1" "$exit_code"

output=$( ( MISSING_FILES=("x.dll"); report_missing "SDK file(s)" ) 2>&1 ) || true
assert_eq "output contains the missing file name" "1" "$(echo "$output" | grep -c 'x.dll')"

# ── e2e: full script with mocked SDK ─────────────────────────────────────────
#
# This test exercises the complete script end-to-end without a real Windows SDK
# by building a directory tree that mirrors the Windows SDK layout.

echo ""
echo "▶ e2e: full script with mocked SDK"

E2E_DIR="$TMPDIR_ROOT/e2e"
MOCK_SDK="$E2E_DIR/sdk"
E2E_OUT="$E2E_DIR/out"

mkdir -p "$E2E_OUT"

SDK_VER="10.0.99999.0"
ARCHS=("x86" "x64" "arm64")
SDK_FILES=(
    "appxpackaging.dll" "makeappx.exe" "makecert.exe" "makecat.exe"
    "makecat.exe.manifest"
    "Microsoft.Windows.Build.Signing.mssign32.dll.manifest" "mssign32.dll"
    "Microsoft.Windows.Build.Appx.AppxSip.dll.manifest" "appxsip.dll"
    "Microsoft.Windows.Build.Signing.wintrust.dll.manifest" "wintrust.dll"
    "makepri.exe"
    "Microsoft.Windows.Build.Appx.AppxPackaging.dll.manifest"
    "Microsoft.Windows.Build.Appx.OpcServices.dll.manifest" "opcservices.dll"
    "signtool.exe" "signtool.exe.manifest" "pvk2pfx.exe"
)

# Populate mock SDK
for arch in "${ARCHS[@]}"; do
    mkdir -p "$MOCK_SDK/$SDK_VER/$arch"
    for f in "${SDK_FILES[@]}"; do
        echo "mock-$f" > "$MOCK_SDK/$SDK_VER/$arch/$f"
    done
done

# Run the script
E2E_EXIT=0
E2E_OUTPUT=$(
    WINDOWS_KIT_PATH="$MOCK_SDK" \
    bash "$SCRIPT" --output-dir "$E2E_OUT" 2>&1
) || E2E_EXIT=$?

assert_eq "e2e: script exits 0" "0" "$E2E_EXIT"

ZIP_VERSION="${SDK_VER//./_}"
PRODUCED_ZIP=$(find "$E2E_OUT" -name "windows-kits-bundle-${ZIP_VERSION}.zip" 2>/dev/null | head -1)

if [ -n "$PRODUCED_ZIP" ]; then
    echo "  ✅ e2e: output ZIP created ($PRODUCED_ZIP)"
    PASS=$(( PASS + 1 ))

    ZIP_LIST=$(unzip -l "$PRODUCED_ZIP" 2>/dev/null)

    # signtool.exe in every arch dir
    for arch in "${ARCHS[@]}"; do
        if echo "$ZIP_LIST" | grep -q "$arch/signtool.exe"; then
            echo "  ✅ e2e: ZIP contains $arch/signtool.exe"
            PASS=$(( PASS + 1 ))
        else
            echo "  ❌ e2e: ZIP missing $arch/signtool.exe"
            FAIL=$(( FAIL + 1 ))
        fi
    done

    if echo "$ZIP_LIST" | grep -q "VERSION.txt"; then
        echo "  ✅ e2e: ZIP contains VERSION.txt"
        PASS=$(( PASS + 1 ))
    else
        echo "  ❌ e2e: ZIP missing VERSION.txt"
        FAIL=$(( FAIL + 1 ))
    fi

    # ATS files must NOT be in the kits bundle
    if echo "$ZIP_LIST" | grep -q "Azure.CodeSigning.Dlib.dll"; then
        echo "  ❌ e2e: kits ZIP unexpectedly contains ATS payload"
        FAIL=$(( FAIL + 1 ))
    else
        echo "  ✅ e2e: kits ZIP contains no ATS payload"
        PASS=$(( PASS + 1 ))
    fi

    rm -f "$PRODUCED_ZIP"
else
    echo "  ❌ e2e: expected ZIP not found"
    echo "  Script output:"
    echo "$E2E_OUTPUT" | sed 's/^/    /'
    FAIL=$(( FAIL + 1 ))
fi

# ── e2e: named-arg CLI ────────────────────────────────────────────────────────

echo ""
echo "▶ e2e: named-arg CLI"

# --help exits 1 and prints usage
HELP_EXIT=0
HELP_OUT=$(bash "$SCRIPT" --help 2>&1) || HELP_EXIT=$?
assert_eq "--help exits 1" "1" "$HELP_EXIT"
assert_eq "--help prints Usage:" "1" "$(echo "$HELP_OUT" | grep -c 'Usage:')"

# Unknown flag exits 1
UNKNOWN_EXIT=0
bash "$SCRIPT" --unknown-flag 2>/dev/null || UNKNOWN_EXIT=$?
assert_eq "unknown flag exits 1" "1" "$UNKNOWN_EXIT"

# --sdk-path overrides WINDOWS_KIT_PATH env var
SDK_PATH_OUT=$(( WINDOWS_KIT_PATH="/env-only-path" bash "$SCRIPT" --sdk-path "/cli-override-path" ) 2>&1) || true
assert_eq "--sdk-path overrides env WINDOWS_KIT_PATH" "0" "$(echo "$SDK_PATH_OUT" | grep -c '/env-only-path')"

# ── e2e: error paths ──────────────────────────────────────────────────────────

echo ""
echo "▶ e2e: error paths"

E2E_ERR=0
( WINDOWS_KIT_PATH="/nonexistent/path" bash "$SCRIPT" ) >/dev/null 2>&1 || E2E_ERR=$?
assert_eq "exits 1 when SDK directory missing" "1" "$E2E_ERR"

# ── Results ───────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════"
echo "Results: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════"
[ "$FAIL" -eq 0 ]
