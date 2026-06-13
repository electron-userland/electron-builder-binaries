#!/usr/bin/env bash
# Unit + e2e + Wine smoke tests for build-win-dotnet.sh.
# Run: bash packages/win-codesign/test/build-win-dotnet-test.sh
set -uo pipefail

PASS=0
FAIL=0
SKIP=0
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../assets" && pwd)/build-win-dotnet.sh"
PACKAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

skip() {
    echo "  [SKIP] $*"
    SKIP=$(( SKIP + 1 ))
}

# ── Setup ─────────────────────────────────────────────────────────────────────

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# Source helpers only (main body is gated by BASH_SOURCE guard)
# shellcheck source=../assets/build-win-dotnet.sh
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

# ── e2e: full script with mocked download ─────────────────────────────────────
#
# Exercises the complete script end-to-end without network access by:
#   1. Creating a minimal zip mirroring the real .NET runtime layout.
#   2. Injecting a fake `curl` via PATH that copies the pre-built zip.

echo ""
echo "▶ e2e: full script with mocked download"

E2E_DIR="$TMPDIR_ROOT/e2e"
MOCK_ZIP_SRC="$E2E_DIR/dotnet-src"
MOCK_ZIP="$E2E_DIR/mock-dotnet.zip"
FAKE_BIN="$E2E_DIR/fake-bin"
E2E_OUT="$E2E_DIR/out"

mkdir -p "$FAKE_BIN" "$E2E_OUT"

# Minimal layout mirroring the real win-x64 runtime zip
mkdir -p "$MOCK_ZIP_SRC/host/fxr/8.0.28"
mkdir -p "$MOCK_ZIP_SRC/shared/Microsoft.NETCore.App/8.0.28"
echo "mock-dotnet-exe"       > "$MOCK_ZIP_SRC/dotnet.exe"
echo "mock-license"          > "$MOCK_ZIP_SRC/LICENSE.txt"
echo "mock-third-party"      > "$MOCK_ZIP_SRC/ThirdPartyNotices.txt"
echo "mock-hostfxr"          > "$MOCK_ZIP_SRC/host/fxr/8.0.28/hostfxr.dll"
echo "mock-coreclr"          > "$MOCK_ZIP_SRC/shared/Microsoft.NETCore.App/8.0.28/coreclr.dll"

(cd "$MOCK_ZIP_SRC" && zip -r -q "$MOCK_ZIP" .)

if command -v sha256sum >/dev/null 2>&1; then
    MOCK_SHA256=$(sha256sum "$MOCK_ZIP" | awk '{print $1}')
else
    MOCK_SHA256=$(shasum -a 256 "$MOCK_ZIP" | awk '{print $1}')
fi

# Fake curl: ignores all flags, copies pre-built zip to --output path
cat > "$FAKE_BIN/curl" << 'FAKE_CURL'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output|-o) OUTPUT="$2"; shift 2 ;;
        *) shift ;;
    esac
done
cp "$MOCK_DOTNET_ZIP" "$OUTPUT"
FAKE_CURL
chmod +x "$FAKE_BIN/curl"

E2E_EXIT=0
E2E_OUTPUT=$(
    MOCK_DOTNET_ZIP="$MOCK_ZIP" \
    PATH="$FAKE_BIN:$PATH" \
    DOTNET_VERSION="0.0.0" \
    DOTNET_SHA256="$MOCK_SHA256" \
    bash "$SCRIPT" --output-dir "$E2E_OUT" 2>&1
) || E2E_EXIT=$?

assert_eq "e2e: script exits 0" "0" "$E2E_EXIT"

PRODUCED_ZIP=$(find "$E2E_OUT" -name "dotnet-runtime-win-x64-*.zip" 2>/dev/null | head -1)

if [ -n "$PRODUCED_ZIP" ]; then
    echo "  ✅ e2e: output ZIP created ($PRODUCED_ZIP)"
    PASS=$(( PASS + 1 ))

    ZIP_LIST=$(unzip -l "$PRODUCED_ZIP" 2>/dev/null)

    for f in "dotnet.exe" "LICENSE.txt" "ThirdPartyNotices.txt" "VERSION.txt"; do
        if echo "$ZIP_LIST" | grep -q "$f"; then
            echo "  ✅ e2e: ZIP contains $f"
            PASS=$(( PASS + 1 ))
        else
            echo "  ❌ e2e: ZIP missing $f"
            FAIL=$(( FAIL + 1 ))
        fi
    done

    if echo "$ZIP_LIST" | grep -q "host/fxr"; then
        echo "  ✅ e2e: ZIP contains host/fxr directory"
        PASS=$(( PASS + 1 ))
    else
        echo "  ❌ e2e: ZIP missing host/fxr directory"
        FAIL=$(( FAIL + 1 ))
    fi

    if echo "$ZIP_LIST" | grep -q "shared/Microsoft.NETCore.App"; then
        echo "  ✅ e2e: ZIP contains shared/Microsoft.NETCore.App directory"
        PASS=$(( PASS + 1 ))
    else
        echo "  ❌ e2e: ZIP missing shared/Microsoft.NETCore.App directory"
        FAIL=$(( FAIL + 1 ))
    fi

    # VERSION.txt must record the requested version
    VERSION_CONTENTS=$(unzip -p "$PRODUCED_ZIP" VERSION.txt 2>/dev/null || true)
    if echo "$VERSION_CONTENTS" | grep -q "dotnet_version: 0.0.0"; then
        echo "  ✅ e2e: VERSION.txt records dotnet_version"
        PASS=$(( PASS + 1 ))
    else
        echo "  ❌ e2e: VERSION.txt missing or wrong dotnet_version"
        FAIL=$(( FAIL + 1 ))
    fi

    rm -f "$PRODUCED_ZIP"
else
    echo "  ❌ e2e: expected dotnet-runtime-win-x64-*.zip not found"
    echo "  Script output:"
    echo "$E2E_OUTPUT" | sed 's/^/    /'
    FAIL=$(( FAIL + 1 ))
fi

# ── e2e: named-arg CLI ────────────────────────────────────────────────────────

echo ""
echo "▶ e2e: named-arg CLI"

HELP_EXIT=0
HELP_OUT=$(bash "$SCRIPT" --help 2>&1) || HELP_EXIT=$?
assert_eq "--help exits 1" "1" "$HELP_EXIT"
assert_eq "--help prints Usage:" "1" "$(echo "$HELP_OUT" | grep -c 'Usage:')"

UNKNOWN_EXIT=0
bash "$SCRIPT" --unknown-flag 2>/dev/null || UNKNOWN_EXIT=$?
assert_eq "unknown flag exits 1" "1" "$UNKNOWN_EXIT"

# ── e2e: --output-dir ─────────────────────────────────────────────────────────

E2E_CUSTOM_OUT="$TMPDIR_ROOT/custom-out"
mkdir -p "$E2E_CUSTOM_OUT"

E2E_CUSTOM_EXIT=0
(
    MOCK_DOTNET_ZIP="$MOCK_ZIP" \
    PATH="$FAKE_BIN:$PATH" \
    DOTNET_VERSION="0.0.0" \
    DOTNET_SHA256="$MOCK_SHA256" \
    bash "$SCRIPT" --output-dir "$E2E_CUSTOM_OUT" 2>&1
) || E2E_CUSTOM_EXIT=$?
assert_eq "e2e: --output-dir: script exits 0" "0" "$E2E_CUSTOM_EXIT"

CUSTOM_ZIP=$(find "$E2E_CUSTOM_OUT" -name "dotnet-runtime-win-x64-*.zip" 2>/dev/null | head -1)
if [ -n "$CUSTOM_ZIP" ]; then
    echo "  ✅ e2e: --output-dir: ZIP written to custom location"
    PASS=$(( PASS + 1 ))
    rm -f "$CUSTOM_ZIP"
else
    echo "  ❌ e2e: --output-dir: ZIP not found in $E2E_CUSTOM_OUT"
    FAIL=$(( FAIL + 1 ))
fi

# ── e2e: error paths ──────────────────────────────────────────────────────────

echo ""
echo "▶ e2e: error paths"

E2E_SHA_ERR=0
(
    MOCK_DOTNET_ZIP="$MOCK_ZIP" \
    PATH="$FAKE_BIN:$PATH" \
    DOTNET_VERSION="0.0.0" \
    DOTNET_SHA256="0000000000000000000000000000000000000000000000000000000000000000" \
    bash "$SCRIPT"
) >/dev/null 2>&1 || E2E_SHA_ERR=$?
assert_eq "exits 1 when checksum mismatches" "1" "$E2E_SHA_ERR"

# Missing required file (dotnet.exe absent) → script exits 1
MOCK_INCOMPLETE_SRC="$TMPDIR_ROOT/incomplete-src"
MOCK_INCOMPLETE_ZIP="$TMPDIR_ROOT/incomplete.zip"
mkdir -p "$MOCK_INCOMPLETE_SRC"
echo "no-dotnet-exe" > "$MOCK_INCOMPLETE_SRC/LICENSE.txt"
echo "no-dotnet-exe" > "$MOCK_INCOMPLETE_SRC/ThirdPartyNotices.txt"
(cd "$MOCK_INCOMPLETE_SRC" && zip -r -q "$MOCK_INCOMPLETE_ZIP" .)

if command -v sha256sum >/dev/null 2>&1; then
    INCOMPLETE_SHA=$(sha256sum "$MOCK_INCOMPLETE_ZIP" | awk '{print $1}')
else
    INCOMPLETE_SHA=$(shasum -a 256 "$MOCK_INCOMPLETE_ZIP" | awk '{print $1}')
fi

E2E_MISSING_EXIT=0
(
    MOCK_DOTNET_ZIP="$MOCK_INCOMPLETE_ZIP" \
    PATH="$FAKE_BIN:$PATH" \
    DOTNET_VERSION="0.0.0" \
    DOTNET_SHA256="$INCOMPLETE_SHA" \
    bash "$SCRIPT" --output-dir "$TMPDIR_ROOT/missing-out"
) >/dev/null 2>&1 || E2E_MISSING_EXIT=$?
assert_eq "exits 1 when dotnet.exe missing from zip" "1" "$E2E_MISSING_EXIT"

# ── Wine smoke test ───────────────────────────────────────────────────────────
# Requires: a real bundle produced by build-win-dotnet.sh + wine in PATH + DISPLAY.
# Skips cleanly if any prerequisite is absent.

echo ""
echo "▶ Wine smoke test"

REAL_BUNDLE=$(find "$PACKAGE_DIR/out/win-codesign" -name "dotnet-runtime-win-x64-*.zip" 2>/dev/null | head -1)

if [ -z "$REAL_BUNDLE" ]; then
    skip "wine smoke test (no produced bundle — run build-win-dotnet.sh first)"
else
    WINE_BIN=""
    for candidate in wine wine64; do
        if command -v "$candidate" >/dev/null 2>&1; then
            WINE_BIN="$candidate"
            break
        fi
    done

    if [ -z "$WINE_BIN" ]; then
        skip "wine smoke test (no wine binary in PATH)"
    else
        # Basic sanity: can wine launch a Windows process at all?
        WINE_SANE=0
        timeout 20 "$WINE_BIN" cmd.exe /c exit 2>/dev/null || WINE_SANE=$?
        if [ "$WINE_SANE" -ne 0 ]; then
            skip "wine smoke test (wine sanity check failed — likely Rosetta/QEMU emulation)"
        else
            SMOKE_DOTNET="$TMPDIR_ROOT/smoke-dotnet"
            SMOKE_PREFIX="$TMPDIR_ROOT/smoke-prefix"
            mkdir -p "$SMOKE_DOTNET" "$SMOKE_PREFIX"

            unzip -q "$REAL_BUNDLE" -d "$SMOKE_DOTNET"

            # Initialize prefix (Wine needs a prefix even for console apps)
            WINEPREFIX="$SMOKE_PREFIX" WINEARCH=win64 WINEDEBUG=-all \
                "$WINE_BIN" wineboot --init 2>/dev/null || true

            # Z: maps to host filesystem root under Wine
            WIN_DOTNET_EXE="Z:$(echo "$SMOKE_DOTNET/dotnet.exe" | tr '/' '\\')"

            SMOKE_EXIT=0
            SMOKE_OUT=$(
                WINEPREFIX="$SMOKE_PREFIX" WINEDEBUG=-all \
                    "$WINE_BIN" "$WIN_DOTNET_EXE" --info 2>&1
            ) || SMOKE_EXIT=$?

            if [ "$SMOKE_EXIT" -eq 0 ] && echo "$SMOKE_OUT" | grep -qi "Microsoft.NETCore.App"; then
                echo "  ✅ wine smoke test: dotnet --info exited 0 and reported NETCore.App runtime"
                PASS=$(( PASS + 1 ))
            else
                echo "  ❌ wine smoke test: dotnet --info failed (exit=$SMOKE_EXIT)"
                echo "$SMOKE_OUT" | head -10 | sed 's/^/     /'
                FAIL=$(( FAIL + 1 ))
            fi
        fi
    fi
fi

# ── Results ───────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════"
TOTAL=$(( PASS + FAIL + SKIP ))
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped ($TOTAL total)"
echo "═══════════════════════════════════════"
[ "$FAIL" -eq 0 ]
