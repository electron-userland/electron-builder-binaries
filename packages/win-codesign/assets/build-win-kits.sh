#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── Helpers (sourceable for testing) ─────────────────────────────────────────

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
  --output-dir    Output directory for the bundle ZIP
                  (default: <package-root>/out/win-codesign)
  -h|--help       Show this help
EOF
    exit 1
}

# Defaults — CLI flags take precedence over env vars, env vars over built-in defaults
SDK_BASE="${WINDOWS_KIT_PATH:-C:/Program Files (x86)/Windows Kits/10/bin}"
OUTPUT_DIR="$SCRIPT_DIR/out/win-codesign"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sdk-path)   SDK_BASE="$2";   shift 2 ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        -h|--help)    usage ;;
        *)            echo "❌ Unknown argument: $1" >&2; usage ;;
    esac
done

BUNDLE_DIR="$OUTPUT_DIR/windows-kits-bundle"

# When sourced for testing, stop here so helpers are importable without side effects.
[[ "${BASH_SOURCE[0]}" == "${0}" ]] || return 0

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

# ── ZIP ───────────────────────────────────────────────────────────────────────
{
    echo "bundle: windows-kits"
    echo "created_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo ""
    echo "version: $VERSION"
} > "$BUNDLE_DIR/VERSION.txt"

echo "📦 Zipping windows-kits..."
ASSETS_ZIP="$OUTPUT_DIR/windows-kits-bundle-${VERSION//./_}.zip"

cd "$BUNDLE_DIR"
zip -r -9 "$ASSETS_ZIP" .
rm -rf "$BUNDLE_DIR"

echo "✅ Created bundle: $ASSETS_ZIP"
echo ""
