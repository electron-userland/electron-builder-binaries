#!/usr/bin/env bash
# Unit + e2e tests for build-win-ats.sh helpers and full script flow.
# Run: bash packages/win-codesign/test/build-win-ats-test.sh
set -uo pipefail

PASS=0
FAIL=0
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../assets" && pwd)/build-win-ats.sh"

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
# shellcheck source=../assets/build-win-ats.sh
source "$SCRIPT"

# ── verify_sha256 ─────────────────────────────────────────────────────────────

echo ""
echo "▶ verify_sha256"

TMP_FILE="$TMPDIR_ROOT/test-hash.txt"
echo -n "hello" > "$TMP_FILE"

if command -v sha256sum >/dev/null 2>&1; then
    HELLO_SHA256=$(sha256sum "$TMP_FILE" | awk '{print $1}')
else
    HELLO_SHA256=$(shasum -a 256 "$TMP_FILE" | awk '{print $1}')
fi

assert_exit "passes when hash matches"    0 verify_sha256 "$TMP_FILE" "$HELLO_SHA256"
assert_exit "fails when hash is wrong"    1 verify_sha256 "$TMP_FILE" "0000000000000000000000000000000000000000000000000000000000000000"
assert_exit "fails when file is missing"  1 verify_sha256 "$TMPDIR_ROOT/nonexistent.txt" "$HELLO_SHA256"

# ── e2e: full script with mocked NuGet package ───────────────────────────────
#
# This test exercises the complete script end-to-end without network access by:
#   1. Creating a minimal .nupkg (zip) with the expected ATS DLL paths inside.
#   2. Injecting a fake `curl` via PATH that copies the pre-built nupkg.

echo ""
echo "▶ e2e: full script with mocked NuGet"

E2E_DIR="$TMPDIR_ROOT/e2e"
MOCK_NUPKG_DIR="$E2E_DIR/nupkg-src"
MOCK_NUPKG="$E2E_DIR/mock.nupkg"
FAKE_BIN="$E2E_DIR/fake-bin"
E2E_OUT="$E2E_DIR/out"

mkdir -p "$FAKE_BIN" "$E2E_OUT"

# The dlib plus a sample of its dependency closure — the script must copy the
# whole bin/<arch> directory, not just the dlib.
ATS_FILES=(
    "Azure.CodeSigning.Dlib.dll"
    "Azure.CodeSigning.dll"
    "Ijwhost.dll"
    "Azure.CodeSigning.Dlib.runtimeconfig.json"
    "msvcp140.dll"
)

# Build mock nupkg mirroring real package: only x64 and x86 (no arm64 bin).
NUPKG_ARCHS=("x86" "x64")
for arch in "${NUPKG_ARCHS[@]}"; do
    mkdir -p "$MOCK_NUPKG_DIR/bin/$arch"
    for dll in "${ATS_FILES[@]}"; do
        echo "mock-$dll" > "$MOCK_NUPKG_DIR/bin/$arch/$dll"
    done
done
(cd "$MOCK_NUPKG_DIR" && zip -r -q "$MOCK_NUPKG" .)

# Compute hash of the mock nupkg (exercises verification against a known-good hash)
if command -v sha256sum >/dev/null 2>&1; then
    MOCK_NUPKG_SHA256=$(sha256sum "$MOCK_NUPKG" | awk '{print $1}')
else
    MOCK_NUPKG_SHA256=$(shasum -a 256 "$MOCK_NUPKG" | awk '{print $1}')
fi

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

# Run the script
E2E_EXIT=0
E2E_OUTPUT=$(
    MOCK_NUPKG_PATH="$MOCK_NUPKG" \
    PATH="$FAKE_BIN:$PATH" \
    ATS_NUGET_VERSION="0.0.0" \
    ATS_NUGET_SHA256="$MOCK_NUPKG_SHA256" \
    bash "$SCRIPT" --output-dir "$E2E_OUT" 2>&1
) || E2E_EXIT=$?

assert_eq "e2e: script exits 0" "0" "$E2E_EXIT"

PRODUCED_ZIP=$(find "$E2E_OUT" -name "ats-bundle-*.zip" 2>/dev/null | head -1)

if [ -n "$PRODUCED_ZIP" ]; then
    echo "  ✅ e2e: output ZIP created ($PRODUCED_ZIP)"
    PASS=$(( PASS + 1 ))

    ZIP_LIST=$(unzip -l "$PRODUCED_ZIP" 2>/dev/null)

    # Full ATS dependency closure in x86 and x64 (not just the dlib)
    for arch in "${NUPKG_ARCHS[@]}"; do
        for f in "${ATS_FILES[@]}"; do
            if echo "$ZIP_LIST" | grep -q "$arch/$f"; then
                echo "  ✅ e2e: ZIP contains $arch/$f"
                PASS=$(( PASS + 1 ))
            else
                echo "  ❌ e2e: ZIP missing $arch/$f"
                FAIL=$(( FAIL + 1 ))
            fi
        done
    done

    # arm64 must NOT carry the x64 ATS payload (would shadow native signtool DLLs)
    for f in "Azure.CodeSigning.Dlib.dll" "msvcp140.dll"; do
        if echo "$ZIP_LIST" | grep -q "arm64/$f"; then
            echo "  ❌ e2e: ZIP unexpectedly contains arm64/$f"
            FAIL=$(( FAIL + 1 ))
        else
            echo "  ✅ e2e: ZIP excludes arm64/$f"
            PASS=$(( PASS + 1 ))
        fi
    done

    if echo "$ZIP_LIST" | grep -q "VERSION.txt"; then
        echo "  ✅ e2e: ZIP contains VERSION.txt"
        PASS=$(( PASS + 1 ))
    else
        echo "  ❌ e2e: ZIP missing VERSION.txt"
        FAIL=$(( FAIL + 1 ))
    fi

    # Verify temp files were cleaned up
    SCRIPT_PARENT="$(cd "$(dirname "$SCRIPT")/.." && pwd)"
    assert_file_missing "e2e: ATS nupkg cleaned up" "$SCRIPT_PARENT/out/win-codesign/ats-client.nupkg"

    rm -f "$PRODUCED_ZIP"
else
    echo "  ❌ e2e: expected ats-bundle-*.zip not found"
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

# --ats-version overrides ATS_NUGET_VERSION env var
ATS_VER_OUT=$(( ATS_NUGET_VERSION="9.9.9" bash "$SCRIPT" --ats-version "1.2.3" ) 2>&1) || true
assert_eq "--ats-version overrides env ATS_NUGET_VERSION" "0" "$(echo "$ATS_VER_OUT" | grep -c '9\.9\.9')"

# ── e2e: --output-dir ─────────────────────────────────────────────────────────

E2E_CUSTOM_OUT="$TMPDIR_ROOT/custom-out"
mkdir -p "$E2E_CUSTOM_OUT"

E2E_CUSTOM_EXIT=0
(
    MOCK_NUPKG_PATH="$MOCK_NUPKG" \
    PATH="$FAKE_BIN:$PATH" \
    ATS_NUGET_VERSION="0.0.0" \
    ATS_NUGET_SHA256="$MOCK_NUPKG_SHA256" \
    bash "$SCRIPT" --output-dir "$E2E_CUSTOM_OUT" 2>&1
) || E2E_CUSTOM_EXIT=$?
assert_eq "e2e: --output-dir: script exits 0" "0" "$E2E_CUSTOM_EXIT"

CUSTOM_ZIP=$(find "$E2E_CUSTOM_OUT" -name "ats-bundle-*.zip" 2>/dev/null | head -1)
if [ -n "$CUSTOM_ZIP" ]; then
    echo "  ✅ e2e: --output-dir: ZIP written to custom location ($CUSTOM_ZIP)"
    PASS=$(( PASS + 1 ))
    rm -f "$CUSTOM_ZIP"
else
    echo "  ❌ e2e: --output-dir: ZIP not found in $E2E_CUSTOM_OUT"
    FAIL=$(( FAIL + 1 ))
fi

# ── e2e: error paths ──────────────────────────────────────────────────────────

echo ""
echo "▶ e2e: error paths"

# Wrong nupkg checksum must fail closed (the script pins a default SHA-256)
E2E_SHA_ERR=0
(
    MOCK_NUPKG_PATH="$MOCK_NUPKG" \
    PATH="$FAKE_BIN:$PATH" \
    ATS_NUGET_VERSION="0.0.0" \
    ATS_NUGET_SHA256="0000000000000000000000000000000000000000000000000000000000000000" \
    bash "$SCRIPT"
) >/dev/null 2>&1 || E2E_SHA_ERR=$?
assert_eq "exits 1 when nupkg checksum mismatches" "1" "$E2E_SHA_ERR"

# ── Results ───────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════"
echo "Results: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════"
[ "$FAIL" -eq 0 ]
