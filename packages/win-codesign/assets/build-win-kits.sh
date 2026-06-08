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

# Copy src_root/ARCH/file → dest_root/ARCH/file for all ARCHITECTURES.
# Args: src_root dest_root [file ...]
# Reads global: ARCHITECTURES
# Appends to global: MISSING_FILES
copy_arch_files() {
    local src_root="$1" dest_root="$2"
    shift 2
    local copied=0 arch f src dest

    for arch in "${ARCHITECTURES[@]}"; do
        mkdir -p "$dest_root/$arch"
        for f in "$@"; do
            src="$src_root/$arch/$f"
            dest="$dest_root/$arch/$f"
            if [ -f "$src" ]; then
                cp "$src" "$dest"
                echo "  ✅ $arch/$f"
                copied=$(( copied + 1 ))
            else
                echo "  ⚠️  Not found: $src"
                MISSING_FILES+=("$src")
            fi
        done
    done
    echo "  Copied: $copied file(s)"
}

# Print list and exit 1 if MISSING_FILES is non-empty.
report_missing() {
    local label="${1:-file(s)}"
    if [ "${#MISSING_FILES[@]}" -gt 0 ]; then
        echo ""
        echo "❌ Error: ${#MISSING_FILES[@]} ${label} not found:"
        for f in "${MISSING_FILES[@]}"; do
            echo "  - $f"
        done
        exit 1
    fi
}

# ── CLI ───────────────────────────────────────────────────────────────────────

usage() {
    cat >&2 << EOF
Usage: $0 [options]
  --sdk-path      Windows Kits bin/ directory
                  (default: \$WINDOWS_KIT_PATH or 'C:/Program Files (x86)/Windows Kits/10/bin')
  --ats-version   Microsoft.Trusted.Signing.Client NuGet version
                  (default: \$ATS_NUGET_VERSION or '1.0.95')
  --ats-sha256    Expected SHA-256 of the .nupkg; omit to skip verification
                  (default: \$ATS_NUGET_SHA256)
  --output-dir    Output directory for the bundle ZIP
                  (default: <package-root>/out/win-codesign)
  -h|--help       Show this help
EOF
    exit 1
}

# Defaults — CLI flags take precedence over env vars, env vars over built-in defaults
SDK_BASE="${WINDOWS_KIT_PATH:-C:/Program Files (x86)/Windows Kits/10/bin}"
ATS_NUGET_VERSION="${ATS_NUGET_VERSION:-1.0.95}"
ATS_NUGET_SHA256="${ATS_NUGET_SHA256:-}"
OUTPUT_DIR="$SCRIPT_DIR/out/win-codesign"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sdk-path)    SDK_BASE="$2";          shift 2 ;;
        --ats-version) ATS_NUGET_VERSION="$2"; shift 2 ;;
        --ats-sha256)  ATS_NUGET_SHA256="$2";  shift 2 ;;
        --output-dir)  OUTPUT_DIR="$2";        shift 2 ;;
        -h|--help)     usage ;;
        *)             echo "❌ Unknown argument: $1" >&2; usage ;;
    esac
done

BUNDLE_DIR="$OUTPUT_DIR/windows-kits-bundle"
ATS_NUPKG="$OUTPUT_DIR/ats-client.nupkg"
ATS_EXTRACT="$OUTPUT_DIR/ats-client"

# When sourced for testing, stop here so helpers are importable without side effects.
[[ "${BASH_SOURCE[0]}" == "${0}" ]] || return 0

# ── Cleanup on exit ───────────────────────────────────────────────────────────
cleanup() {
    rm -rf "$ATS_EXTRACT"
    rm -f "$ATS_NUPKG"
}
trap cleanup EXIT

# ── Windows SDK files ─────────────────────────────────────────────────────────

echo "📦 Creating Windows Kits bundle..."

rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR"

cp -a "$SCRIPT_DIR/assets/appxAssets" "$BUNDLE_DIR/appxAssets"

echo "SDK base directory: $SDK_BASE"

if [ ! -d "$SDK_BASE" ]; then
    echo "❌ Error: SDK base directory not found: $SDK_BASE"
    exit 1
fi

VERSION=$(ls -1 "$SDK_BASE" 2>/dev/null | grep '^10\.' | sort -V | tail -n1)
if [ -z "$VERSION" ]; then
    echo "❌ Error: No Windows SDK version found in directory."
    echo "Directory contents:"
    ls -1 "$SDK_BASE" 2>/dev/null || echo "(directory listing failed)"
    exit 1
fi

echo "Using Windows SDK version: $VERSION"
echo "Source: $SDK_BASE/$VERSION  →  Destination: $BUNDLE_DIR"

ARCHITECTURES=("x86" "x64" "arm64")
FILES=(
    "appxpackaging.dll"
    "makeappx.exe"
    "makecert.exe"
    "makecat.exe"
    "makecat.exe.manifest"
    "Microsoft.Windows.Build.Signing.mssign32.dll.manifest"
    "mssign32.dll"
    "Microsoft.Windows.Build.Appx.AppxSip.dll.manifest"
    "appxsip.dll"
    "Microsoft.Windows.Build.Signing.wintrust.dll.manifest"
    "wintrust.dll"
    "makepri.exe"
    "Microsoft.Windows.Build.Appx.AppxPackaging.dll.manifest"
    "Microsoft.Windows.Build.Appx.OpcServices.dll.manifest"
    "opcservices.dll"
    "signtool.exe"
    "signtool.exe.manifest"
    "pvk2pfx.exe"
)
MISSING_FILES=()

echo "Copying Windows SDK files..."
copy_arch_files "$SDK_BASE/$VERSION" "$BUNDLE_DIR" "${FILES[@]}"
report_missing "Windows SDK file(s)"

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

# v1.0.95+ ships bin/x64 and bin/x86 only (no bin/arm64).
# For arm64 bundles we copy the x64 binaries — Wine on arm64 Windows runs x64 DLLs.
ATS_DLLS=(
    "Azure.CodeSigning.Dlib.dll"
)
MISSING_FILES=()

echo "Copying ATS DLLs..."
for arch in "${ARCHITECTURES[@]}"; do
    ats_src_arch="$arch"
    [[ "$arch" == "arm64" ]] && ats_src_arch="x64"
    mkdir -p "$BUNDLE_DIR/$arch"
    for dll in "${ATS_DLLS[@]}"; do
        src="$ATS_EXTRACT/bin/$ats_src_arch/$dll"
        if [ -f "$src" ]; then
            cp "$src" "$BUNDLE_DIR/$arch/$dll"
            echo "  ✅ $arch/$dll"
        else
            echo "  ⚠️  Not found: $src"
            MISSING_FILES+=("$src")
        fi
    done
done
report_missing "ATS DLL(s)"

rm -rf "$ATS_EXTRACT"

# ── VERSION.txt ───────────────────────────────────────────────────────────────
{
    echo "bundle: windows-kits"
    echo "created_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo ""
    echo "version: $VERSION"
    echo "ats_client_version: ${ATS_NUGET_VERSION}"
} > "$BUNDLE_DIR/VERSION.txt"

# ── ZIP ───────────────────────────────────────────────────────────────────────
echo "📦 Zipping appxAssets + windows-kits..."
ASSETS_ZIP="$OUTPUT_DIR/windows-kits-bundle-${VERSION//./_}.zip"

cd "$BUNDLE_DIR"
zip -r -9 "$ASSETS_ZIP" .

echo "✅ Created bundle: $ASSETS_ZIP"
echo ""

rm -rf "$BUNDLE_DIR"
