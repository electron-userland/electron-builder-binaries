#!/usr/bin/env bash
# e2e tests for build-win-rcedit.sh with a mocked download (no network):
#   - the EXEs and the LICENSE are fetched from the same release tag (v<version>), never from master
#   - the bundle ships the LICENSE in the scripts/verify-licenses.sh layout and the guard passes
#   - an empty LICENSE download fails the build
# Run: bash packages/win-codesign/test/build-win-rcedit-test.sh
# shellcheck disable=SC2001 # sed indents every line of multi-line output; ${var//...} cannot anchor at line starts
set -uo pipefail

PASS=0
FAIL=0
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../assets" && pwd)/build-win-rcedit.sh"

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

sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

MOCK="$TMPDIR_ROOT/mock"
FAKE_BIN="$TMPDIR_ROOT/fake-bin"
mkdir -p "$MOCK" "$FAKE_BIN"
# "MZ" so the license guard treats the mocks as binaries
printf 'MZmock-rcedit-x64\n' > "$MOCK/rcedit-x64.exe"
printf 'MZmock-rcedit-x86\n' > "$MOCK/rcedit-x86.exe"
printf 'mock MIT License\n' > "$MOCK/LICENSE"
: > "$MOCK/LICENSE-empty"

# Fake curl: serves the mock file named by the URL's last path segment and logs every URL
cat > "$FAKE_BIN/curl" << 'FAKE_CURL'
#!/usr/bin/env bash
URL="" OUTPUT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output|-o) OUTPUT="$2"; shift 2 ;;
        http*) URL="$1"; shift ;;
        *) shift ;;
    esac
done
echo "$URL" >> "$MOCK_CURL_LOG"
name="${URL##*/}"
[[ "$name" == LICENSE ]] && name="$MOCK_LICENSE_NAME"
cp "$MOCK_DIR/$name" "$OUTPUT"
FAKE_CURL
chmod +x "$FAKE_BIN/curl"

run_script() {
    local out="$1" license_name="$2"
    MOCK_DIR="$MOCK" MOCK_LICENSE_NAME="$license_name" MOCK_CURL_LOG="$TMPDIR_ROOT/curl.log" \
    PATH="$FAKE_BIN:$PATH" \
    bash "$SCRIPT" --version 9.8.7 \
        --x64-sha256 "$(sha256 "$MOCK/rcedit-x64.exe")" \
        --x86-sha256 "$(sha256 "$MOCK/rcedit-x86.exe")" \
        --output-dir "$out" 2>&1
}

echo ""
echo "▶ e2e: full script with mocked download"

: > "$TMPDIR_ROOT/curl.log"
E2E_OUT="$TMPDIR_ROOT/out"
E2E_EXIT=0
E2E_OUTPUT=$(run_script "$E2E_OUT" LICENSE) || E2E_EXIT=$?
assert_eq "script exits 0" "0" "$E2E_EXIT"
[ "$E2E_EXIT" = 0 ] || echo "$E2E_OUTPUT" | sed 's/^/    /'

ZIP="$E2E_OUT/rcedit-windows-9_8_7.zip"
assert_eq "LICENSE is fetched from the v9.8.7 tag" "1" \
    "$(grep -cxF 'https://raw.githubusercontent.com/electron/rcedit/v9.8.7/LICENSE' "$TMPDIR_ROOT/curl.log")"
assert_eq "nothing is fetched from master" "0" "$(grep -c '/master/' "$TMPDIR_ROOT/curl.log")"
assert_eq "LICENSES/rcedit/LICENSE ships" "mock MIT License" "$(unzip -p "$ZIP" LICENSES/rcedit/LICENSE 2>/dev/null)"
assert_eq "LICENSES/MANIFEST.tsv lists both EXEs" "rcedit-x64.exe	rcedit
rcedit-x86.exe	rcedit" "$(unzip -p "$ZIP" LICENSES/MANIFEST.tsv 2>/dev/null | grep -v '^#')"
assert_eq "LICENSES/SOURCES.tsv points at the release tag" "rcedit	9.8.7	https://github.com/electron/rcedit/tree/v9.8.7" \
    "$(unzip -p "$ZIP" LICENSES/SOURCES.tsv 2>/dev/null | grep -v '^#')"
assert_eq "no download leftovers in the zip" "0" "$(unzip -l "$ZIP" 2>/dev/null | grep -c '\.download')"
assert_eq "the license guard ran" "1" "$(echo "$E2E_OUTPUT" | grep -c '✓ All 2 binaries have license files')"

echo ""
echo "▶ e2e: error paths"

EMPTY_OUT="$TMPDIR_ROOT/out-empty"
EMPTY_EXIT=0
EMPTY_OUTPUT=$(run_script "$EMPTY_OUT" LICENSE-empty) || EMPTY_EXIT=$?
assert_eq "exits 1 when the LICENSE download is empty" "1" "$EMPTY_EXIT"
assert_eq "names the empty LICENSE" "1" "$(echo "$EMPTY_OUTPUT" | grep -c 'License file for rcedit is missing or empty')"
assert_eq "writes no zip" "" "$(find "$EMPTY_OUT" -name '*.zip' 2>/dev/null)"

echo ""
echo "═══════════════════════════════════════"
echo "Results: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════"
[ "$FAIL" -eq 0 ]
