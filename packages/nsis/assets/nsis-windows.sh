#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Windows NSIS Base Bundle Builder (Cross-Platform)
# =============================================================================
# Downloads official pre-built NSIS for Windows and packages with plugins
# This creates the BASE bundle with Windows binary and all shared data
# Runs on Linux/Mac/Windows via bash
# =============================================================================

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
OUT_DIR="$BASE_DIR/out/nsis"
TEMP_DIR="$OUT_DIR/temp"

# Version configuration
NSIS_VERSION=${NSIS_VERSION:-3.11}
NSIS_BRANCH=${NSIS_BRANCH_OR_COMMIT:-v311}

BUNDLE_DIR="$OUT_DIR/nsis-bundle"
OUTPUT_ARCHIVE="$OUT_DIR/nsis-bundle-base-$NSIS_BRANCH.tar.gz"

echo "📦 Building NSIS Base Bundle (strlen_8192)..."
echo "   Version: $NSIS_VERSION"
echo "   Branch:  $NSIS_BRANCH"
echo ""

# =============================================================================
# Setup Directories
# =============================================================================

echo "🧹 Setting up directories..."
rm -rf "$TEMP_DIR" "$BUNDLE_DIR"
mkdir -p "$TEMP_DIR" "$BUNDLE_DIR/windows"

# =============================================================================
# Check Dependencies
# =============================================================================

if ! command -v curl &> /dev/null; then
    echo "❌ curl is required but not installed"
    exit 1
fi

if ! command -v tar &> /dev/null; then
    echo "❌ tar is required but not installed"
    exit 1
fi

if ! command -v rsync &> /dev/null; then
    echo "❌ rsync is required but not installed"
    exit 1
fi

# =============================================================================
# Download Official NSIS
# =============================================================================

echo ""
echo "📥 Downloading official NSIS $NSIS_VERSION from SourceForge..."

NSIS_ZIP_URL="https://sourceforge.net/projects/nsis/files/NSIS%203/$NSIS_VERSION/nsis-$NSIS_VERSION.zip/download"
NSIS_ZIP="$TEMP_DIR/nsis-$NSIS_VERSION.zip"

if ! curl -L "$NSIS_ZIP_URL" -o "$NSIS_ZIP" --progress-bar; then
    echo "❌ Failed to download NSIS"
    exit 1
fi

echo "  ✓ Downloaded $(du -h "$NSIS_ZIP" | cut -f1)"

# =============================================================================
# Download NSIS strlen_8192 Patch
# =============================================================================

echo ""
echo "📥 Downloading NSIS $NSIS_VERSION strlen_8192 patch..."

STRLEN_ZIP_URL="https://sourceforge.net/projects/nsis/files/NSIS%203/$NSIS_VERSION/nsis-$NSIS_VERSION-strlen_8192.zip/download"
STRLEN_ZIP="$TEMP_DIR/nsis-$NSIS_VERSION-strlen_8192.zip"

if ! curl -L "$STRLEN_ZIP_URL" -o "$STRLEN_ZIP" --progress-bar; then
    echo "❌ Failed to download strlen_8192 patch"
    exit 1
fi

echo "  ✓ Downloaded $(du -h "$STRLEN_ZIP" | cut -f1)"

# =============================================================================
# Extract NSIS
# =============================================================================

echo ""
echo "📂 Extracting NSIS..."

if ! unzip -q "$NSIS_ZIP" -d "$TEMP_DIR"; then
    echo "❌ Failed to extract NSIS"
    exit 1
fi

NSIS_EXTRACTED="$TEMP_DIR/nsis-$NSIS_VERSION"

if [ ! -d "$NSIS_EXTRACTED" ]; then
    echo "❌ NSIS directory not found after extraction"
    exit 1
fi

echo "  ✓ Extracted base NSIS"

# =============================================================================
# Extract and Apply strlen_8192 Patch
# =============================================================================

echo ""
echo "🔧 Extracting and applying strlen_8192 patch..."

STRLEN_EXTRACTED="$TEMP_DIR/nsis-$NSIS_VERSION-strlen_8192"
mkdir -p "$STRLEN_EXTRACTED"

if ! unzip -q "$STRLEN_ZIP" -d "$STRLEN_EXTRACTED"; then
    echo "❌ Failed to extract strlen_8192 patch"
    exit 1
fi

# Patch over the base NSIS files using rsync
echo "  → Patching NSIS files"
rsync -a "$STRLEN_EXTRACTED/" "$NSIS_EXTRACTED/"

echo "  ✓ Applied strlen_8192 patch"

# =============================================================================
# Copy NSIS Data Files
# =============================================================================

echo ""
echo "📚 Copying NSIS data files..."

for item in Bin Contrib Include Plugins Stubs; do
    if [ -d "$NSIS_EXTRACTED/$item" ]; then
        echo "  → $item/"
        rsync -a "$NSIS_EXTRACTED/$item/" "$BUNDLE_DIR/windows/$item/"
    fi
done

echo "  → Installing root-level files"
rsync -a "$NSIS_EXTRACTED/"*.{exe,dll,nsh} "$BUNDLE_DIR/windows/" 2>/dev/null || true

echo "  ✓ Copied NSIS data files"

# =============================================================================
# Download Additional Plugins
# =============================================================================

echo ""
echo "🔌 Downloading additional plugins..."

PLUGINS_DIR="$TEMP_DIR/plugins"
mkdir -p "$PLUGINS_DIR"

# Plugin configuration (Bash 3.2 compatible - using parallel arrays)
PLUGIN_NAMES=(
    "INetC"
    "StdUtils"
    "SpiderBanner"
    "NsProcess"
    "UAC"
    "WinShell"
    "NsJSON"
    "NsArray"
    "NsisMultiUser"
    "EmbedHTML"
    "Nsisunz"
    "NSISunzU"
)

PLUGIN_URLS=(
    "https://github.com/DigitalMediaServer/NSIS-INetC-plugin/releases/download/v1.0.5.6/INetC.zip"
    "https://github.com/lordmulder/stdutils/releases/download/1.14/StdUtils.2018-10-27.zip"
    "https://nsis.sourceforge.io/mediawiki/images/4/4c/SpiderBanner_plugin.zip"
    "https://nsis.sourceforge.io/mediawiki/images/1/18/NsProcess.zip"
    "https://nsis.sourceforge.io/mediawiki/images/8/8f/UAC.zip"
    "https://nsis.sourceforge.io/mediawiki/images/5/54/WinShell.zip"
    "https://nsis.sourceforge.io/mediawiki/images/5/5a/NsJSON.zip"
    "https://nsis.sourceforge.io/mediawiki/images/4/4c/NsArray.zip"
    "https://nsis.sourceforge.io/mediawiki/images/5/5d/NsisMultiUser.zip"
    "https://nsis.sourceforge.io/mediawiki/images/7/7c/EmbedHTML.zip"
    "https://nsis.sourceforge.io/mediawiki/images/1/1c/Nsisunz.zip"
    "https://nsis.sourceforge.io/mediawiki/images/5/5a/NSISunzU.zip"
)

# Special handling for nsis7z (7z archive)
NSIS7Z_URL="https://nsis.sourceforge.io/mediawiki/images/6/69/Nsis7z_19.00.7z"

DOWNLOADED_COUNT=0

# Download regular plugins
for i in "${!PLUGIN_NAMES[@]}"; do
    plugin_name="${PLUGIN_NAMES[$i]}"
    plugin_url="${PLUGIN_URLS[$i]}"
    plugin_zip="$PLUGINS_DIR/${plugin_name}.zip"
    
    echo "  → $plugin_name"
    
    if curl -sL "$plugin_url" -o "$plugin_zip"; then
        DOWNLOADED_COUNT=$((DOWNLOADED_COUNT + 1))
    else
        echo "    ⚠️  Failed to download"
    fi
done

# Download nsis7z separately (7z format)
echo "  → nsis7z"
if curl -sL "$NSIS7Z_URL" -o "$PLUGINS_DIR/nsis7z.7z"; then
    DOWNLOADED_COUNT=$((DOWNLOADED_COUNT + 1))
else
    echo "    ⚠️  Failed to download nsis7z"
fi

echo "  ✓ Downloaded $DOWNLOADED_COUNT plugins"

# =============================================================================
# Install Plugins
# =============================================================================

echo ""
echo "🔧 Installing plugins..."

# Determine extraction tool
if command -v 7z &> /dev/null; then
    EXTRACT_CMD="7z"
    EXTRACT_ARGS="x -y"
elif command -v 7za &> /dev/null; then
    EXTRACT_CMD="7za"
    EXTRACT_ARGS="x -y"
else
    EXTRACT_CMD="unzip"
    EXTRACT_ARGS="-q -o"
fi

# Create plugin directories
mkdir -p "$BUNDLE_DIR/windows/Plugins"/{x64-ansi,x64-unicode,x86-ansi,x86-unicode}
mkdir -p "$BUNDLE_DIR/windows/Include"

# Process ZIP plugins
for plugin_zip in "$PLUGINS_DIR"/*.zip; do
    test -f "$plugin_zip" || continue
    
    plugin_name=$(basename "$plugin_zip" .zip)
    extract_dir="$PLUGINS_DIR/$plugin_name"
    
    mkdir -p "$extract_dir"
    
    # Extract (suppress output)
    if test "$EXTRACT_CMD" = "unzip"; then
        $EXTRACT_CMD $EXTRACT_ARGS "$plugin_zip" -d "$extract_dir" >/dev/null 2>&1 || true
    else
        $EXTRACT_CMD $EXTRACT_ARGS "$plugin_zip" -o"$extract_dir" >/dev/null 2>&1 || true
    fi
    
    # Install DLL files using rsync with better filtering
    # Skip common test/example/tiny directories
    if [ -d "$extract_dir/Plugins" ]; then
        # Standard plugin structure with Plugins/ directory
        for arch_dir in "$extract_dir/Plugins"/*; do
            [ -d "$arch_dir" ] || continue
            arch_name=$(basename "$arch_dir")
            
            case "$arch_name" in
                x64-ansi|x64-unicode|x86-ansi|x86-unicode)
                    rsync -a --include='*.dll' --exclude='*' "$arch_dir/" "$BUNDLE_DIR/windows/Plugins/$arch_name/"
                    ;;
                ANSI64)
                    rsync -a --include='*.dll' --exclude='*' "$arch_dir/" "$BUNDLE_DIR/windows/Plugins/x64-ansi/"
                    ;;
                Unicode64)
                    rsync -a --include='*.dll' --exclude='*' "$arch_dir/" "$BUNDLE_DIR/windows/Plugins/x64-unicode/"
                    ;;
                [Aa]nsi|ANSI)
                    rsync -a --include='*.dll' --exclude='*' "$arch_dir/" "$BUNDLE_DIR/windows/Plugins/x86-ansi/"
                    ;;
                [Uu]nicode|Unicode)
                    rsync -a --include='*.dll' --exclude='*' "$arch_dir/" "$BUNDLE_DIR/windows/Plugins/x86-unicode/"
                    ;;
            esac
        done
    else
        # Find DLLs with improved heuristics - exclude test/example/tiny dirs
        find "$extract_dir" -type f -name "*.dll" \
            ! -path "*/[Tt]iny/*" \
            ! -path "*/[Ee]xample*/*" \
            ! -path "*/[Tt]est*/*" \
            ! -path "*/[Dd]emo*/*" \
            ! -path "*/[Dd]oc*/*" \
            ! -path "*/.git/*" \
            2>/dev/null | while read -r dll_file; do
            
            dll_path=$(dirname "$dll_file")
            dll_basename=$(basename "$dll_file")
            
            # Determine architecture by path
            if echo "$dll_path" | grep -qiE 'x64.*(ansi|ANSI)'; then
                cp "$dll_file" "$BUNDLE_DIR/windows/Plugins/x64-ansi/" 2>/dev/null || true
            elif echo "$dll_path" | grep -qiE 'x64.*(unicode|Unicode)'; then
                cp "$dll_file" "$BUNDLE_DIR/windows/Plugins/x64-unicode/" 2>/dev/null || true
            elif echo "$dll_path" | grep -qiE 'x86.*(unicode|Unicode)|unicode|Unicode'; then
                cp "$dll_file" "$BUNDLE_DIR/windows/Plugins/x86-unicode/" 2>/dev/null || true
            elif echo "$dll_path" | grep -qiE 'x86.*(ansi|ANSI)|ansi|ANSI'; then
                cp "$dll_file" "$BUNDLE_DIR/windows/Plugins/x86-ansi/" 2>/dev/null || true
            else
                # Filename-based heuristics
                if echo "$dll_basename" | grep -qE 'W\.dll$|Unicode|unicode'; then
                    cp "$dll_file" "$BUNDLE_DIR/windows/Plugins/x86-unicode/" 2>/dev/null || true
                elif echo "$plugin_name" | grep -qiE 'NSISunzU'; then
                    cp "$dll_file" "$BUNDLE_DIR/windows/Plugins/x86-unicode/" 2>/dev/null || true
                else
                    cp "$dll_file" "$BUNDLE_DIR/windows/Plugins/x86-ansi/" 2>/dev/null || true
                fi
            fi
        done
    fi
    
    # Install header files using rsync
    rsync -a --include='*.nsh' --exclude='*' \
        --exclude='[Ee]xample*/' --exclude='[Tt]est*/' --exclude='[Dd]emo*/' \
        "$extract_dir/" "$BUNDLE_DIR/windows/Include/" 2>/dev/null || true
    
    # Install .nsi files (exclude examples/tests/demos)
    find "$extract_dir" -type f -name "*.nsi" \
        ! -ipath '*example*' \
        ! -ipath '*test*' \
        ! -ipath '*demo*' \
        ! -ipath '*doc*' \
        -exec cp {} "$BUNDLE_DIR/windows/Include/" \; 2>/dev/null || true
    
    echo "  ✓ $plugin_name"
done

# Process nsis7z (7z archive)
if test -f "$PLUGINS_DIR/nsis7z.7z"; then
    nsis7z_dir="$PLUGINS_DIR/nsis7z"
    mkdir -p "$nsis7z_dir"
    
    if test "$EXTRACT_CMD" = "unzip"; then
        echo "  ⚠️  Cannot extract .7z files without 7z/7za - skipping nsis7z"
    else
        $EXTRACT_CMD $EXTRACT_ARGS "$PLUGINS_DIR/nsis7z.7z" -o"$nsis7z_dir" >/dev/null 2>&1 || true
        
        # Install nsis7z DLLs using rsync
        for arch in x64-unicode x86-ansi x86-unicode; do
            if [ -d "$nsis7z_dir/Plugins/$arch" ]; then
                rsync -a --include='nsis7z.dll' --exclude='*' \
                    "$nsis7z_dir/Plugins/$arch/" "$BUNDLE_DIR/windows/Plugins/$arch/"
            fi
        done
        
        # Install headers using rsync
        rsync -a --include='*.nsh' --exclude='*' \
            "$nsis7z_dir/" "$BUNDLE_DIR/windows/Include/" 2>/dev/null || true
        
        echo "  ✓ nsis7z"
    fi
fi

# =============================================================================
# Apply Language File Patches
# =============================================================================

echo ""
echo "🔧 Applying language file patches..."

FIXES_DIR="$BASE_DIR/assets/nsis-lang-fixes"
LANG_FILES_DIR="$BUNDLE_DIR/windows/Contrib/Language files"

PATCHED_COUNT=0
ls -1 "$LANG_FILES_DIR"/*.n* >/dev/null 2>&1 || {
    echo "  ⚠️  No language files found to patch"
    exit 1
}

for fixfile in "$FIXES_DIR"/*; do
    [ -f "$fixfile" ] || continue
    
    fname=$(basename "$fixfile")
    target="$LANG_FILES_DIR/$fname"
    
    if [ -f "$target" ]; then
        echo "  → Patching $fname"
        {
            echo ""
            echo ""
            echo "; --- BEGIN FIXES ADDED ---"
            echo ""
            cat "$fixfile"
            echo ""
            echo "; --- END FIXES ADDED ---"
            echo ""
        } >> "$target"
        ((PATCHED_COUNT++)) || true
    fi
done

if [ $PATCHED_COUNT -gt 0 ]; then
    echo "  ✓ Patched $PATCHED_COUNT language files"
else
    echo "  ⚠️  No language files to patch"
    exit 1
fi

# =============================================================================
# Create Version Metadata
# =============================================================================

cat > "$BUNDLE_DIR/windows/VERSION.txt" <<EOF
Platform: Windows
Binary: makensis.exe (official pre-built with strlen_8192 patch)
Architecture: x86 (runs on all Windows via WoW64)
Max String Length: 8192
EOF

# =============================================================================
# Create Archive
# =============================================================================

echo ""
echo "📦 Creating base bundle archive..."

cd "$OUT_DIR"
tar -czf "${OUTPUT_ARCHIVE}" nsis-bundle

# =============================================================================
# Cleanup
# =============================================================================

rm -rf "$TEMP_DIR"

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "================================================================"
echo "  ✅ Base Bundle Complete (strlen_8192)!"
echo "================================================================"
echo "  📁 Archive: $OUTPUT_ARCHIVE"
echo "  📊 Size:    $(du -h "$OUTPUT_ARCHIVE" | cut -f1)"

if [ -d "$BUNDLE_DIR/windows/Plugins" ]; then
    plugin_count=$(find "$BUNDLE_DIR/windows/Plugins" -name "*.dll" 2>/dev/null | wc -l | xargs)
    echo "  🔌 Plugins: $plugin_count DLLs"
fi

echo "================================================================"
echo ""