#!/usr/bin/env bash
# Unit + e2e tests for build-win-kits.sh helpers, named-arg parsing, and full script flow.
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

assert_file_missing() {
    local desc="$1" path="$2"
    if [ ! -f "$path" ]; then
        echo "  ✅ $desc"
        PASS=$(( PASS + 1 ))
    else
        echo "  ❌ $desc (unexpectedly present: $path)"
        FAIL=$(( FAIL + 1 ))
    fi
}

# ── Setup ─────────────────────────────────────────────────────────────────────

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# Source helpers only (main body is gated by BASH_SOURCE guard)
# shellcheck source=../assets/build-win-kits.sh
source "$SCRIPT"

# ── verify_sha256 ─────────────────────────────────────────────────────────────

echo ""
echo "▶ verify_sha256"

TMP_FILE="$TMPDIR_ROOT/test-hash.txt"
echo -n "hello" > "$TMP_FILE"

# Compute the expected hash portably
if command -v sha256sum >/dev/null 2>&1; then
    HELLO_SHA256=$(sha256sum "$TMP_FILE" | awk '{print $1}')
else
    HELLO_SHA256=$(shasum -a 256 "$TMP_FILE" | awk '{print $1}')
fi

assert_exit "passes when hash matches"    0 verify_sha256 "$TMP_FILE" "$HELLO_SHA256"
assert_exit "fails when hash is wrong"    1 verify_sha256 "$TMP_FILE" "0000000000000000000000000000000000000000000000000000000000000000"
assert_exit "fails when file is missing"  1 verify_sha256 "$TMPDIR_ROOT/nonexistent.txt" "$HELLO_SHA256"

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

# ── e2e: full script with mocked SDK and NuGet package ───────────────────────
#
# This test exercises the complete script end-to-end without network access or
# a real Windows SDK by:
#   1. Building a directory tree that mirrors the Windows SDK layout.
#   2. Creating a minimal .nupkg (zip) with the expected ATS DLL paths inside.
#   3. Injecting a fake `curl` via PATH that copies the pre-built nupkg.
#   4. Running the script with WINDOWS_KIT_PATH pointing at the mock SDK.

echo ""
echo "▶ e2e: full script with mocked SDK and NuGet"

E2E_DIR="$TMPDIR_ROOT/e2e"
MOCK_SDK="$E2E_DIR/sdk"
MOCK_NUPKG_DIR="$E2E_DIR/nupkg-src"
MOCK_NUPKG="$E2E_DIR/mock.nupkg"
FAKE_BIN="$E2E_DIR/fake-bin"
E2E_OUT="$E2E_DIR/out"

mkdir -p "$FAKE_BIN" "$E2E_OUT"

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
ATS_DLLS=("Azure.CodeSigning.Dlib.dll")

# Populate mock SDK
for arch in "${ARCHS[@]}"; do
    mkdir -p "$MOCK_SDK/$SDK_VER/$arch"
    for f in "${SDK_FILES[@]}"; do
        echo "mock-$f" > "$MOCK_SDK/$SDK_VER/$arch/$f"
    done
done

# Build mock nupkg mirroring real package: only x64 and x86 (no arm64 bin).
# The script maps arm64 → x64 source when copying ATS DLLs.
NUPKG_ARCHS=("x86" "x64")
for arch in "${NUPKG_ARCHS[@]}"; do
    mkdir -p "$MOCK_NUPKG_DIR/bin/$arch"
    for dll in "${ATS_DLLS[@]}"; do
        echo "mock-$dll" > "$MOCK_NUPKG_DIR/bin/$arch/$dll"
    done
done
(cd "$MOCK_NUPKG_DIR" && zip -r -q "$MOCK_NUPKG" .)

# Fake curl: ignores all flags, copies pre-built nupkg to --output path
cat > "$FAKE_BIN/curl" << 'FAKE_CURL'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output|-o) OUTPUT="$2"; shift 2 ;;
        *) shift ;;
    esac
done
cp "$MOCK_NUPKG_PATH" "$OUTPUT"
FAKE_CURL
chmod +x "$FAKE_BIN/curl"

# Point the script at the mock environment and run it
E2E_EXIT=0
E2E_OUTPUT=$(
    MOCK_NUPKG_PATH="$MOCK_NUPKG" \
    PATH="$FAKE_BIN:$PATH" \
    WINDOWS_KIT_PATH="$MOCK_SDK" \
    ATS_NUGET_VERSION="0.0.0" \
    bash "$SCRIPT" 2>&1
) || E2E_EXIT=$?

assert_eq "e2e: script exits 0" "0" "$E2E_EXIT"

# Find the produced ZIP (name contains SDK version with dots replaced by underscores)
ZIP_VERSION="${SDK_VER//./_}"
PRODUCED_ZIP=$(find "$E2E_OUT" -name "windows-kits-bundle-${ZIP_VERSION}.zip" 2>/dev/null | head -1)

if [ -z "$PRODUCED_ZIP" ]; then
    # Script writes to its own out/ dir; locate it relative to SCRIPT_DIR
    SCRIPT_PARENT="$(cd "$(dirname "$SCRIPT")/.." && pwd)"
    PRODUCED_ZIP=$(find "$SCRIPT_PARENT/out" -name "windows-kits-bundle-${ZIP_VERSION}.zip" 2>/dev/null | head -1)
fi

if [ -n "$PRODUCED_ZIP" ]; then
    echo "  ✅ e2e: output ZIP created ($PRODUCED_ZIP)"
    PASS=$(( PASS + 1 ))

    # Verify expected files are inside the ZIP
    ZIP_LIST=$(unzip -l "$PRODUCED_ZIP" 2>/dev/null)
    for arch in "${ARCHS[@]}"; do
        for f in "signtool.exe" "Azure.CodeSigning.Dlib.dll"; do
            if echo "$ZIP_LIST" | grep -q "$arch/$f"; then
                echo "  ✅ e2e: ZIP contains $arch/$f"
                PASS=$(( PASS + 1 ))
            else
                echo "  ❌ e2e: ZIP missing $arch/$f"
                FAIL=$(( FAIL + 1 ))
            fi
        done
    done

    if echo "$ZIP_LIST" | grep -q "VERSION.txt"; then
        echo "  ✅ e2e: ZIP contains VERSION.txt"
        PASS=$(( PASS + 1 ))
    else
        echo "  ❌ e2e: ZIP missing VERSION.txt"
        FAIL=$(( FAIL + 1 ))
    fi

    # Verify temp dirs were cleaned up
    SCRIPT_PARENT="$(cd "$(dirname "$SCRIPT")/.." && pwd)"
    assert_file_missing "e2e: ATS nupkg cleaned up" "$SCRIPT_PARENT/out/win-codesign/ats-client.nupkg"

    # Clean up produced output
    rm -f "$PRODUCED_ZIP"
    rm -rf "$SCRIPT_PARENT/out/win-codesign/windows-kits-bundle"
else
    echo "  ❌ e2e: expected ZIP not found"
    echo "  Script output:"
    echo "$E2E_OUTPUT" | sed 's/^/    /'
    FAIL=$(( FAIL + 1 ))
fi

# ── e2e: named-arg CLI interface ─────────────────────────────────────────────

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

# --sdk-path overrides WINDOWS_KIT_PATH env var — the env-path must not appear in output
SDK_PATH_OUT=$(( WINDOWS_KIT_PATH="/env-only-path" bash "$SCRIPT" --sdk-path "/cli-override-path" ) 2>&1) || true
assert_eq "--sdk-path overrides env WINDOWS_KIT_PATH" "0" "$(echo "$SDK_PATH_OUT" | grep -c '/env-only-path')"

# e2e: --output-dir redirects ZIP to a custom location
E2E_CUSTOM_OUT="$TMPDIR_ROOT/custom-out"
mkdir -p "$E2E_CUSTOM_OUT"

E2E_CUSTOM_EXIT=0
(
    MOCK_NUPKG_PATH="$MOCK_NUPKG" \
    PATH="$FAKE_BIN:$PATH" \
    WINDOWS_KIT_PATH="$MOCK_SDK" \
    ATS_NUGET_VERSION="0.0.0" \
    bash "$SCRIPT" --output-dir "$E2E_CUSTOM_OUT" 2>&1
) || E2E_CUSTOM_EXIT=$?
assert_eq "e2e: --output-dir: script exits 0" "0" "$E2E_CUSTOM_EXIT"

CUSTOM_ZIP=$(find "$E2E_CUSTOM_OUT" -name "windows-kits-bundle-*.zip" 2>/dev/null | head -1)
if [ -n "$CUSTOM_ZIP" ]; then
    echo "  ✅ e2e: --output-dir: ZIP written to custom location ($CUSTOM_ZIP)"
    PASS=$(( PASS + 1 ))
    rm -f "$CUSTOM_ZIP"
else
    echo "  ❌ e2e: --output-dir: ZIP not found in $E2E_CUSTOM_OUT"
    FAIL=$(( FAIL + 1 ))
fi

# ── e2e: missing SDK directory ────────────────────────────────────────────────

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
