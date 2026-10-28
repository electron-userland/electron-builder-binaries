#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── Helpers (sourceable for testing) ─────────────────────────────────────────

verify_sha256() {
    local file="$1" expected="$2" actual
    if [ ! -f "$file" ]; then
        echo "❌ File not found: $file" >&2
        return 1
    fi
    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "$file" | awk '{print $1}') || { echo "❌ sha256sum failed for $(basename "$file")" >&2; return 1; }
    elif command -v shasum >/dev/null 2>&1; then
        actual=$(shasum -a 256 "$file" | awk '{print $1}') || { echo "❌ shasum failed for $(basename "$file")" >&2; return 1; }
    else
        echo "❌ No sha256 tool found (sha256sum or shasum required)" >&2
        return 1
    fi
    if [ "$actual" = "$expected" ]; then
        echo "  ✓ Checksum verified"
    else
        echo "❌ Checksum mismatch for $(basename "$file")" >&2
        echo "   expected: $expected" >&2
        echo "   actual:   $actual" >&2
        return 1
    fi
}

# ── CLI ───────────────────────────────────────────────────────────────────────

usage() {
    cat >&2 << EOF
Usage: $0 [options]
  --dotnet-version  .NET Runtime version to download
                    (default: \$DOTNET_VERSION or '8.0.33')
  --dotnet-sha256   Expected SHA-256 of the downloaded zip. Defaults to the pinned
                    hash of the default --dotnet-version; override when changing
                    --dotnet-version, or pass an empty string to skip verification
                    (not recommended)
                    (default: \$DOTNET_SHA256 or the pinned 8.0.33 hash)
  --output-dir      Output directory for the bundle ZIP
                    (default: <package-root>/out/win-codesign)
  -h|--help         Show this help
EOF
    exit 1
}

# Defaults — CLI flags take precedence over env vars, env vars over built-in defaults
DOTNET_VERSION="${DOTNET_VERSION:-8.0.33}"
# Pinned SHA-256 of dotnet-runtime-8.0.33-win-x64.zip
DOTNET_SHA256="${DOTNET_SHA256:-d88b9624950fd33ffd561462f4a23d7ef6d4173ddef55d198adab07016bc5b8c}"
OUTPUT_DIR="$SCRIPT_DIR/out/win-codesign"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dotnet-version) DOTNET_VERSION="$2"; shift 2 ;;
        --dotnet-sha256)  DOTNET_SHA256="$2";  shift 2 ;;
        --output-dir)     OUTPUT_DIR="$2";     shift 2 ;;
        -h|--help)        usage ;;
        *)                echo "❌ Unknown argument: $1" >&2; usage ;;
    esac
done

DOTNET_ZIP="$OUTPUT_DIR/dotnet-runtime-win-x64.zip"
DOTNET_EXTRACT="$OUTPUT_DIR/dotnet-runtime-extract"

# When sourced for testing, stop here so helpers are importable without side effects.
[[ "${BASH_SOURCE[0]}" == "${0}" ]] || return 0

# ── Cleanup on exit ───────────────────────────────────────────────────────────
cleanup() {
    rm -rf "$DOTNET_EXTRACT"
    rm -f "$DOTNET_ZIP"
}
trap cleanup EXIT

# ── Download ──────────────────────────────────────────────────────────────────

DOTNET_URL="https://builds.dotnet.microsoft.com/dotnet/Runtime/${DOTNET_VERSION}/dotnet-runtime-${DOTNET_VERSION}-win-x64.zip"

mkdir -p "$OUTPUT_DIR"

echo "📦 Downloading .NET Runtime v${DOTNET_VERSION} (win-x64)..."
curl --fail --silent --show-error --location --retry 3 --retry-delay 2 --max-time 120 \
    "$DOTNET_URL" \
    --output "$DOTNET_ZIP"

if [ -n "${DOTNET_SHA256}" ]; then
    echo "  🔍 Verifying checksum..."
    verify_sha256 "$DOTNET_ZIP" "$DOTNET_SHA256"
fi
# Microsoft publishes only SHA-512 hashes (dotnet/core release-notes/<major>/releases.json);
# log it so a new SHA-256 pin can be cross-checked against the official hash.
if command -v sha512sum >/dev/null 2>&1; then
    echo "  sha512: $(sha512sum "$DOTNET_ZIP" | awk '{print $1}')"
fi

# ── Extract and repackage ─────────────────────────────────────────────────────
# The zip layout (dotnet.exe at root, host/fxr/<ver>/, shared/Microsoft.NETCore.App/<ver>/)
# is exactly what DOTNET_ROOT expects — repackage wholesale with a VERSION.txt injected.

mkdir -p "$DOTNET_EXTRACT"
unzip -q "$DOTNET_ZIP" -d "$DOTNET_EXTRACT"
rm -f "$DOTNET_ZIP"

REQUIRED_FILES=("dotnet.exe" "LICENSE.txt" "ThirdPartyNotices.txt")
MISSING_FILES=()
for f in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$DOTNET_EXTRACT/$f" ]; then
        echo "  ⚠️  Not found in zip: $f"
        MISSING_FILES+=("$f")
    fi
done

if [ "${#MISSING_FILES[@]}" -gt 0 ]; then
    echo ""
    echo "❌ Error: ${#MISSING_FILES[@]} expected file(s) not found in the .NET runtime zip:"
    for f in "${MISSING_FILES[@]}"; do
        echo "  - $f"
    done
    exit 1
fi

# ── Licenses ──────────────────────────────────────────────────────────────────
# The runtime's license (LICENSE.txt) and third-party notices (ThirdPartyNotices.txt) from the SHA-256 pinned zip.
# They stay where the zip has them and are also laid out for scripts/verify-licenses.sh; everything in the bundle
# is the .NET runtime as Microsoft ships it.
# shellcheck source=licenses.sh
source "$SCRIPT_DIR/assets/licenses.sh"
license_add "$DOTNET_EXTRACT/LICENSES" dotnet-runtime "$DOTNET_EXTRACT/LICENSE.txt" "$DOTNET_EXTRACT/ThirdPartyNotices.txt"
license_map "$DOTNET_EXTRACT/LICENSES" dotnet-runtime '*'
license_source "$DOTNET_EXTRACT/LICENSES" dotnet-runtime "$DOTNET_VERSION" "$DOTNET_URL"

{
    echo "bundle: dotnet-runtime"
    echo "created_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo ""
    echo "dotnet_version: ${DOTNET_VERSION}"
    echo "arch: win-x64"
} > "$DOTNET_EXTRACT/VERSION.txt"

echo "📦 Zipping dotnet-runtime-win-x64 bundle..."
OUT_ZIP="$OUTPUT_DIR/dotnet-runtime-win-x64-${DOTNET_VERSION//./_}.zip"

(cd "$DOTNET_EXTRACT" && zip -r -9 "$OUT_ZIP" .)
rm -rf "$DOTNET_EXTRACT"

# Every binary in the zip must ship its license (scripts/verify-licenses.sh).
license_verify "$OUT_ZIP"

echo "✅ Created bundle: $OUT_ZIP"
echo ""
