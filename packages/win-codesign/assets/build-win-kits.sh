#!/usr/bin/env bash
set -euo pipefail

CWD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$CWD/out/win-codesign"

echo "📦 Creating Windows Kits bundle..."

ASSETS_BUNDLE_DIR="$OUTPUT_DIR/windows-kits-bundle"
rm -rf "$ASSETS_BUNDLE_DIR"
mkdir -p "$ASSETS_BUNDLE_DIR"

# Copy appxAssets + windows-kits
cp -a "$CWD/assets/appxAssets" "$ASSETS_BUNDLE_DIR/appxAssets"

# Configuration
SDK_BASE="${WINDOWS_KIT_PATH:-C:/Program Files (x86)/Windows Kits/10/bin}"
DESTINATION="$ASSETS_BUNDLE_DIR"

echo "SDK base directory: $SDK_BASE"

# Find the latest Windows SDK version
if [ ! -d "$SDK_BASE" ]; then
    echo "Error: SDK base directory not found: $SDK_BASE"
    exit 1
fi

# List directory contents and find versions starting with "10."
VERSION=$(ls -1 "$SDK_BASE" 2>/dev/null | grep '^10\.' | sort -V | tail -n1)

if [ -z "$VERSION" ]; then
    echo "Error: No Windows SDK version found in directory."
    echo "Directory contents:"
    ls -1 "$SDK_BASE" 2>/dev/null || echo "(directory listing failed)"
    exit 1
fi

echo "Using Windows SDK version: $VERSION"

SOURCE_DIR="$SDK_BASE/$VERSION"
echo "Source directory: $SOURCE_DIR"
echo "Destination directory: $DESTINATION"

# Ensure the destination directory exists
mkdir -p "$DESTINATION"

# Files to copy
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

# Architectures to process
ARCHITECTURES=("x86" "x64" "arm64")

# Array to track missing files
MISSING_FILES=()

# Copy files
echo "Copying files..."
COPIED_COUNT=0

for ARCH in "${ARCHITECTURES[@]}"; do
    mkdir -p "$DESTINATION/$ARCH"
    
    for FILE in "${FILES[@]}"; do
        SRC="$SOURCE_DIR/$ARCH/$FILE"
        DEST="$DESTINATION/$ARCH/$FILE"
        
        if [ -f "$SRC" ]; then
            cp "$SRC" "$DEST"
            echo "✅ Copied $ARCH || $FILE"
            COPIED_COUNT=$(( COPIED_COUNT + 1 ))
        else
            echo "⚠️ Warning: Source file not found: $SRC"
            MISSING_FILES+=("$SRC")
        fi
    done
done

echo "Files copied successfully. Total: $COPIED_COUNT"

# Check for missing files
if [ ${#MISSING_FILES[@]} -gt 0 ]; then
    echo ""
    echo "❌ Error: ${#MISSING_FILES[@]} file(s) were not found:"
    for MISSING_FILE in "${MISSING_FILES[@]}"; do
        echo "  - $MISSING_FILE"
    done
    exit 1
fi

# Create VERSION.txt
{
    echo "bundle: windows-kits"
    echo "created_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo ""
    echo "version: $VERSION"
} > "$ASSETS_BUNDLE_DIR/VERSION.txt"

# Create ZIP archive
echo "📦 Zipping appxAssets + windows-kits..."
ASSETS_ZIP="$OUTPUT_DIR/windows-kits-bundle-${VERSION//./_}.zip"

cd "$ASSETS_BUNDLE_DIR"
zip -r -9 "$ASSETS_ZIP" .

echo "✅ Created bundle: $ASSETS_ZIP"
echo ""

rm -rf "$ASSETS_BUNDLE_DIR"