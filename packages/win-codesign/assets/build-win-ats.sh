#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── Helpers (sourceable for testing) ─────────────────────────────────────────

verify_sha256() {
    local file="$1" expected="$2" actual
    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "$file" | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        actual=$(shasum -a 256 "$file" | awk '{print $1}')
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
  --ats-version   Microsoft.Trusted.Signing.Client NuGet version
                  (default: \$ATS_NUGET_VERSION or '1.0.95')
  --ats-sha256    Expected SHA-256 of the .nupkg. Defaults to the pinned hash of the
                  default --ats-version; override when changing --ats-version, or pass
                  an empty string to skip verification (not recommended)
                  (default: \$ATS_NUGET_SHA256 or the pinned 1.0.95 hash)
  --output-dir    Output directory for the bundle ZIP
                  (default: <package-root>/out/win-codesign)
  -h|--help       Show this help
EOF
    exit 1
}

# Defaults — CLI flags take precedence over env vars, env vars over built-in defaults
ATS_NUGET_VERSION="${ATS_NUGET_VERSION:-1.0.95}"
# Pinned SHA-256 of microsoft.trusted.signing.client.1.0.95.nupkg
ATS_NUGET_SHA256="${ATS_NUGET_SHA256:-3bfcf1e0a3cb42af1692f0a8ed45c15de070c2de86f28a59b2795d904d8a920f}"
OUTPUT_DIR="$SCRIPT_DIR/out/win-codesign"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ats-version) ATS_NUGET_VERSION="$2"; shift 2 ;;
        --ats-sha256)  ATS_NUGET_SHA256="$2";  shift 2 ;;
        --output-dir)  OUTPUT_DIR="$2";        shift 2 ;;
        -h|--help)     usage ;;
        *)             echo "❌ Unknown argument: $1" >&2; usage ;;
    esac
done

ATS_BUNDLE_DIR="$OUTPUT_DIR/ats-bundle"
ATS_NUPKG="$OUTPUT_DIR/ats-client.nupkg"
ATS_EXTRACT="$OUTPUT_DIR/ats-client"

# When sourced for testing, stop here so helpers are importable without side effects.
[[ "${BASH_SOURCE[0]}" == "${0}" ]] || return 0

# ── Cleanup on exit ───────────────────────────────────────────────────────────
cleanup() {
    rm -rf "$ATS_EXTRACT"
    rm -rf "$ATS_BUNDLE_DIR"
    rm -f "$ATS_NUPKG"
}
trap cleanup EXIT

# ── Azure Trusted Signing client DLLs ────────────────────────────────────────
# Azure.CodeSigning.Dlib.dll (and its MSAL auth extension) are NOT part of
# Windows Kits. They ship in the NuGet package Microsoft.Trusted.Signing.Client.
# signtool.exe uses them via /dlib + /dmdf instead of the TrustedSigning
# PowerShell module, enabling cross-platform signing via Wine.

ATS_NUGET_ID="microsoft.trusted.signing.client"

echo "📦 Downloading Microsoft.Trusted.Signing.Client v${ATS_NUGET_VERSION}..."
curl --fail --silent --show-error --location --retry 3 --retry-delay 2 --max-time 120 \
    "https://api.nuget.org/v3-flatcontainer/${ATS_NUGET_ID}/${ATS_NUGET_VERSION}/${ATS_NUGET_ID}.${ATS_NUGET_VERSION}.nupkg" \
    --output "$ATS_NUPKG"

if [ -n "${ATS_NUGET_SHA256}" ]; then
    echo "  🔍 Verifying checksum..."
    verify_sha256 "$ATS_NUPKG" "$ATS_NUGET_SHA256"
fi

mkdir -p "$ATS_EXTRACT"
unzip -q "$ATS_NUPKG" -d "$ATS_EXTRACT"
rm -f "$ATS_NUPKG"

# Azure.CodeSigning.Dlib.dll is a framework-dependent .NET 8 shim — its entire
# dependency closure (Azure.CodeSigning*.dll, Azure.Core/Identity, MSAL, Ijwhost,
# runtimeconfig.json, VC++/MFC runtimes) ships beside it in bin/<arch> and must be
# copied wholesale or signtool /dlib fails to load it at runtime.
#
# v1.0.95+ ships bin/x64 and bin/x86 only (no bin/arm64). arm64 is intentionally
# skipped: the payload is x64-only, and placing x64 runtime DLLs (msvcp140 etc.)
# next to the native arm64 signtool.exe would shadow its own DLL resolution and
# break it. Azure signing on arm64 hosts uses the x64 directory instead (x64
# signtool runs under Windows-on-ARM emulation / x64 Wine).
ATS_ARCHS=("x86" "x64")
ATS_REQUIRED=("Azure.CodeSigning.Dlib.dll")
MISSING_FILES=()

echo "Copying ATS payload (full bin/<arch> dependency closure)..."
for arch in "${ATS_ARCHS[@]}"; do
    src_dir="$ATS_EXTRACT/bin/$arch"
    if [ ! -d "$src_dir" ]; then
        echo "  ⚠️  Not found: $src_dir"
        MISSING_FILES+=("$src_dir")
        continue
    fi
    mkdir -p "$ATS_BUNDLE_DIR/$arch"
    cp -R "$src_dir/." "$ATS_BUNDLE_DIR/$arch/"
    echo "  ✅ $arch: $(ls -1 "$src_dir" | wc -l | tr -d ' ') file(s)"
    for f in "${ATS_REQUIRED[@]}"; do
        if [ ! -f "$ATS_BUNDLE_DIR/$arch/$f" ]; then
            echo "  ⚠️  Not found: $src_dir/$f"
            MISSING_FILES+=("$src_dir/$f")
        fi
    done
done

if [ "${#MISSING_FILES[@]}" -gt 0 ]; then
    echo ""
    echo "❌ Error: ${#MISSING_FILES[@]} ATS file(s) not found:"
    for f in "${MISSING_FILES[@]}"; do
        echo "  - $f"
    done
    exit 1
fi

rm -rf "$ATS_EXTRACT"

# ── ZIP ───────────────────────────────────────────────────────────────────────
{
    echo "bundle: ats"
    echo "created_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo ""
    echo "ats_client_version: ${ATS_NUGET_VERSION}"
} > "$ATS_BUNDLE_DIR/VERSION.txt"

echo "📦 Zipping ats-bundle..."
ATS_ZIP="$OUTPUT_DIR/ats-bundle-${ATS_NUGET_VERSION//./_}.zip"

cd "$ATS_BUNDLE_DIR"
zip -r -9 "$ATS_ZIP" .
rm -rf "$ATS_BUNDLE_DIR"

echo "✅ Created bundle: $ATS_ZIP"
echo ""
