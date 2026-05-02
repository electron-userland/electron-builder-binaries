#!/usr/bin/env bash
set -euo pipefail

CWD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$CWD/out/win-codesign"

RCEDIT_VERSION="${RCEDIT_VERSION:-2.0.0}"
# SHA256 of the pre-built EXEs from electron/rcedit v${RCEDIT_VERSION}.
# Re-pin when bumping RCEDIT_VERSION:
#   curl -fsSL <url-x64> | sha256sum
#   curl -fsSL <url-x86> | sha256sum
RCEDIT_X64_SHA256="${RCEDIT_X64_SHA256:-3e7801db1a5edbec91b49a24a094aad776cb4515488ea5a4ca2289c400eade2a}"
RCEDIT_X86_SHA256="${RCEDIT_X86_SHA256:-38fb5e935d7cb58d7a98b4ed8f876c83f5db032bcd0329b0a4de4e4a1de876b6}"

verify_sha256() {
    local file="$1" expected="$2" actual
    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "$file" | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        actual=$(shasum -a 256 "$file" | awk '{print $1}')
    else
        echo "❌ No sha256 tool found (sha256sum or shasum required)" >&2; return 1
    fi
    if [ "$actual" = "$expected" ]; then
        echo "  ✓ Checksum verified"
        return 0
    else
        echo "❌ Checksum mismatch for $(basename "$file")" >&2
        echo "   expected: $expected" >&2
        echo "   actual:   $actual" >&2
        return 1
    fi
}

mkdir -p "$OUTPUT_DIR/rcedit"

echo "📦 Creating rcedit bundle..."

RCEDIT_BUNDLE_DIR="$OUTPUT_DIR/rcedit"
RCEDIT_ZIP="$OUTPUT_DIR/rcedit-windows-${RCEDIT_VERSION//./_}.zip"

rm -rf "$RCEDIT_BUNDLE_DIR"
mkdir -p "$RCEDIT_BUNDLE_DIR"

BASE_URL="https://github.com/electron/rcedit/releases/download/v${RCEDIT_VERSION}"

echo "📥 Downloading rcedit-x64.exe..."
curl -fsSL --retry 3 --retry-delay 2 --max-time 120 \
    "${BASE_URL}/rcedit-x64.exe" \
    -o "$RCEDIT_BUNDLE_DIR/rcedit-x64.exe"
echo "  🔍 Verifying rcedit-x64.exe checksum..."
verify_sha256 "$RCEDIT_BUNDLE_DIR/rcedit-x64.exe" "$RCEDIT_X64_SHA256"

echo "📥 Downloading rcedit-x86.exe..."
curl -fsSL --retry 3 --retry-delay 2 --max-time 120 \
    "${BASE_URL}/rcedit-x86.exe" \
    -o "$RCEDIT_BUNDLE_DIR/rcedit-x86.exe"
echo "  🔍 Verifying rcedit-x86.exe checksum..."
verify_sha256 "$RCEDIT_BUNDLE_DIR/rcedit-x86.exe" "$RCEDIT_X86_SHA256"

# Create VERSION.txt (without executing the Windows EXEs, which only works on Windows)
{
    echo "bundle: rcedit"
    echo "version: ${RCEDIT_VERSION}"
    echo "created_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo ""
    echo "sha256:"
    echo "  rcedit-x64.exe: ${RCEDIT_X64_SHA256}"
    echo "  rcedit-x86.exe: ${RCEDIT_X86_SHA256}"
} > "$RCEDIT_BUNDLE_DIR/VERSION.txt"

echo "📄 Downloading rcedit LICENSE..."
curl -fsSL --retry 3 --retry-delay 2 --max-time 60 \
    "https://raw.githubusercontent.com/electron/rcedit/master/LICENSE" \
    -o "$RCEDIT_BUNDLE_DIR/LICENSE"

echo "📦 Zipping rcedit bundle..."
cd "$RCEDIT_BUNDLE_DIR"
zip -r -9 "$RCEDIT_ZIP" .

echo "✅ Created bundle: $RCEDIT_ZIP"
echo ""
