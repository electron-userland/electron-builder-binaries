#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# NSIS Bundle Combiner
# =============================================================================
# Combines base, Linux, and macOS bundles into a single complete bundle
# Generates universal entrypoint wrapper script
# =============================================================================

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
OUT_DIR="${OUT_DIR:-$BASE_DIR/out/nsis}"
BUILD_DIR="$(mktemp -d)"

# Version info
NSIS_VERSION=${NSIS_VERSION:-3.12}
NSIS_BRANCH=${NSIS_BRANCH_OR_COMMIT:-v312}

echo "🔗 Combining NSIS bundles..."
echo "   Version: $NSIS_VERSION"
echo "   Branch:  $NSIS_BRANCH"
echo ""

# =============================================================================
# Cleanup and Setup
# =============================================================================

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUT_DIR"

# =============================================================================
# Find Input Bundles
# =============================================================================

echo "📂 Locating bundle files..."

BASE_BUNDLE=$(find "$OUT_DIR" -name "nsis-bundle-base-*.tar.gz" -type f | head -1)
LINUX_BUNDLE=$(find "$OUT_DIR" -name "nsis-bundle-linux-*.tar.gz" -type f | head -1)

# Find Mac bundles - may have different architectures (bash 3.2-compatible, no mapfile)
MAC_BUNDLES=()
while IFS= read -r _line; do
    [[ -n "$_line" ]] && MAC_BUNDLES+=("$_line")
done < <(find "$OUT_DIR" -name "nsis-bundle-mac-*.tar.gz" -type f)
# Validate base bundle
if [ -z "$BASE_BUNDLE" ] || [ ! -f "$BASE_BUNDLE" ]; then
    echo "❌ Base bundle not found in $OUT_DIR"
    exit 1
fi

echo "  ✓ Base:         $(basename "$BASE_BUNDLE")"

if [ -n "$LINUX_BUNDLE" ] && [ -f "$LINUX_BUNDLE" ]; then
    echo "  ✓ Linux:        $(basename "$LINUX_BUNDLE")"
else
    echo "  ⚠️  Linux:        not found (skipping)"
    LINUX_BUNDLE=""
fi

if [ "${#MAC_BUNDLES[@]}" -gt 0 ]; then
    for mac_bundle in "${MAC_BUNDLES[@]}"; do
        echo "  ✓ macOS:        $(basename "$mac_bundle")"
    done
else
    echo "  ⚠️  macOS:        not found (skipping)"
fi

# =============================================================================
# Extract Base Bundle
# =============================================================================

echo ""
echo "📦 Extracting base bundle..."
mkdir -p "$BUILD_DIR"
tar -xzf "$BASE_BUNDLE" -C "$BUILD_DIR"
rm -f "$BASE_BUNDLE"

if [ ! -d "$BUILD_DIR/nsis-bundle" ]; then
    echo "❌ Base bundle extraction failed - nsis-bundle directory not found"
    exit 1
fi

echo "  ✓ Base bundle extracted"

# =============================================================================
# Inject Linux Binary
# =============================================================================

if [ -n "$LINUX_BUNDLE" ]; then
    echo ""
    echo "🐧 Injecting Linux binary..."
    
    TEMP_LINUX="$BUILD_DIR/temp-linux"
    mkdir -p "$TEMP_LINUX"
    
    tar -xzf "$LINUX_BUNDLE" -C "$TEMP_LINUX"
    
    if [ -d "$TEMP_LINUX/nsis-bundle/linux" ]; then
        cp -r "$TEMP_LINUX/nsis-bundle/linux" "$BUILD_DIR/nsis-bundle/"
        echo "  ✓ Linux binary added"
    else
        echo "  ⚠️  Linux binary not found in bundle"
        exit 1
    fi
    
    rm -rf "$TEMP_LINUX" "$LINUX_BUNDLE"
fi

# =============================================================================
# Inject macOS Binaries
# =============================================================================

if [ "${#MAC_BUNDLES[@]}" -gt 0 ]; then
    echo ""
    echo "🍎 Injecting macOS binaries..."

    for mac_bundle in "${MAC_BUNDLES[@]}"; do
        TEMP_MAC="$BUILD_DIR/temp-mac-$$"
        mkdir -p "$TEMP_MAC"
        
        tar -xzf "$mac_bundle" -C "$TEMP_MAC"
        
        if [ -d "$TEMP_MAC/nsis-bundle/mac" ]; then
            arch="${mac_bundle##*-mac-}"
            arch="${arch%%-*}"
            mkdir -p "$BUILD_DIR/nsis-bundle/mac/$arch"
            cp "$TEMP_MAC/nsis-bundle/mac"/* "$BUILD_DIR/nsis-bundle/mac/$arch"
            echo "  ✓ macOS binary added ($(basename "$mac_bundle"))"
        else
            echo "  ⚠️  macOS binary not found in $(basename "$mac_bundle")"
            exit 1
        fi
        
        rm -rf "$TEMP_MAC" "$mac_bundle"
    done

    # Create legacy-compat flat mac/makensis — copies the first available arch binary.
    # Consumers using the old path (mac/makensis) continue to work alongside the
    # arch-specific paths (mac/x64/makensis, mac/arm64/makensis).
    FIRST_MAC_BIN=$(find "$BUILD_DIR/nsis-bundle/mac" -name "makensis" \
        ! -path "$BUILD_DIR/nsis-bundle/mac/makensis" -type f | head -1)
    if [ -n "$FIRST_MAC_BIN" ]; then
        cp "$FIRST_MAC_BIN" "$BUILD_DIR/nsis-bundle/mac/makensis"
        chmod +x "$BUILD_DIR/nsis-bundle/mac/makensis"
        FLAT_ARCH=$(basename "$(dirname "$FIRST_MAC_BIN")")
        echo "  ✓ Legacy mac/makensis created (→ $FLAT_ARCH)"
    fi
fi

# =============================================================================
# Create Universal Entrypoint Wrapper
# =============================================================================

echo ""
echo "🔧 Creating universal entrypoint wrapper..."

cat > "$BUILD_DIR/nsis-bundle/makensis" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------
# Resolve script directory
# ----------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

UNAME_S="$(uname -s)"
UNAME_M="$(uname -m)"

# Normalize ARCH
case "$UNAME_M" in
  x86_64|amd64) ARCH="x86_64" ;;
  arm64|aarch64) ARCH="arm64" ;;
  *) ARCH="$UNAME_M" ;;
esac

# ----------------------------------------
# Platform dispatch
# ----------------------------------------
NSISDIR_WIN=""

case "$UNAME_S" in
  Darwin)
    case "$ARCH" in
      x86_64) ARCH_DIR="x64" ;;
      arm64)  ARCH_DIR="arm64" ;;
      *)      ARCH_DIR="$ARCH" ;;
    esac
    BINARY="$SCRIPT_DIR/mac/$ARCH_DIR/makensis"
    ;;
  Linux)
    BINARY="$SCRIPT_DIR/linux/makensis"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    # makensisw.exe is GUI-subsystem. -VERSION triggers a MessageBox (hangs in
    # headless CI). Read the version from the bundle's VERSION.txt instead.
    # All other invocations (compilation) delegate to makensis.cmd via cmd.exe
    # to avoid MSYS2 path-translation mangling of .nsi file arguments.
    case "${1:-}" in
      -VERSION|-version|/VERSION|/version)
        ver=$(grep -oE "[0-9]+\.[0-9]+" "$SCRIPT_DIR/VERSION.txt" 2>/dev/null | head -1)
        echo "v${ver:-unknown}"
        exit 0
        ;;
    esac
    CMD_WIN=$(cygpath -w "$SCRIPT_DIR/makensis.cmd" 2>/dev/null || echo "$SCRIPT_DIR\\makensis.cmd")
    cmd.exe //c "$CMD_WIN" "$@"
    exit $?
    ;;
  *)
    echo "❌ Unsupported platform: $UNAME_S" >&2
    exit 1
    ;;
esac

# ----------------------------------------
# Validate + execute
# ----------------------------------------
if [ ! -f "$BINARY" ]; then
  echo "❌ makensis binary not found: $BINARY" >&2
  exit 1
fi

if [ ! -x "$BINARY" ]; then
  chmod +x "$BINARY" 2>/dev/null || true
fi

if [ -n "$NSISDIR_WIN" ]; then
  export NSISDIR="$NSISDIR_WIN"
else
  export NSISDIR="$SCRIPT_DIR/windows"
fi

exec "$BINARY" "$@"

EOF

chmod +x "$BUILD_DIR/nsis-bundle/makensis"
echo "  ✓ Created universal makensis wrapper"

# =============================================================================
# Create Windows CMD Entrypoint
# =============================================================================
echo ""
echo "🪟 Creating Windows CMD entrypoint..."

mkdir -p "$BUILD_DIR/nsis-bundle"

cat > "$BUILD_DIR/nsis-bundle/makensis.cmd" <<'EOF'
@echo off
setlocal ENABLEEXTENSIONS

REM =============================================================
REM NSIS Windows CMD Entrypoint
REM =============================================================
REM Delegates to makensis.ps1 via pwsh so that makensisw.exe
REM (GUI subsystem) can be run hidden and auto-closed after compile.
REM =============================================================

set SCRIPT_DIR=%~dp0
set SCRIPT_DIR=%SCRIPT_DIR:~0,-1%

pwsh -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\makensis.ps1" %*
exit /b %ERRORLEVEL%
EOF

# Force CRLF line endings for CMD (always)
tmp_cmd="$BUILD_DIR/nsis-bundle/makensis.cmd.tmp"
sed 's/$/\r/' "$BUILD_DIR/nsis-bundle/makensis.cmd" > "$tmp_cmd"
mv "$tmp_cmd" "$BUILD_DIR/nsis-bundle/makensis.cmd"

echo "  ✓ makensis.cmd created"

# =============================================================================
# Create Windows PowerShell Entrypoint
# =============================================================================
echo ""
echo "🪟 Creating Windows PowerShell entrypoint..."

cat > "$BUILD_DIR/nsis-bundle/makensis.ps1" <<'EOF'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Normalise MSYS2/Git Bash /c/... style paths to Windows C:\... style
if ($ScriptDir -notmatch '^[a-zA-Z]:[\\/]' -and $ScriptDir -match '^/([a-zA-Z])/(.*)') {
    $ScriptDir = "$($matches[1]):\$($matches[2] -replace '/', '\')"
}

$env:NSISDIR = Join-Path $ScriptDir "windows"

$Makensis = Join-Path $env:NSISDIR "makensis.exe"
if (-not (Test-Path $Makensis)) {
    Write-Error "makensis.exe not found at: $Makensis"
    exit 1
}

& $Makensis @args
exit $LASTEXITCODE
EOF

# Force CRLF line endings for PS1 (always)
tmp_ps1="$BUILD_DIR/nsis-bundle/makensis.ps1.tmp"
sed 's/$/\r/' "$BUILD_DIR/nsis-bundle/makensis.ps1" > "$tmp_ps1"
mv "$tmp_ps1" "$BUILD_DIR/nsis-bundle/makensis.ps1"

echo "  ✓ makensis.ps1 created"

# =============================================================================
# Create README
# =============================================================================

echo ""
echo "📝 Creating README..."

cat > "$BUILD_DIR/nsis-bundle/README.md" <<EOF
# NSIS Cross-Platform Bundle

This bundle contains NSIS (Nullsoft Scriptable Install System) binaries for multiple platforms.

## Contents

- **Windows**: \`windows/makensis.exe\` (official pre-built binary)
- **Linux**: \`linux/makensis\` (native ELF binary, compiled from source)
- **macOS**: \`mac/makensis\` (native Mach-O binary, compiled from source)
- **NSIS Data**: \`windows/\` (Contrib, Include, Plugins, Stubs)
- **Universal Wrapper**: \`makensis\` (auto-detects platform, sets \`NSISDIR\`) [.cmd and .ps1 versions for Windows]

## Quick Start

### Option 1: Use Universal Wrapper (Recommended)

The wrapper automatically detects your platform and sets \`NSISDIR\`:

\`\`\`bash
# Linux/macOS/Git Bash
./makensis your-script.nsi

# Windows CMD
makensis.cmd your-script.nsi

# Windows PowerShell
.\makensis.ps1 your-script.nsi
\`\`\`

### Option 2: Use Platform-Specific Binary

\`\`\`bash
# Set NSISDIR manually
export NSISDIR="\$(pwd)/windows"

# Run platform-specific binary
./windows/makensis.exe your-script.nsi  # Windows
./linux/makensis your-script.nsi         # Linux
./mac/makensis your-script.nsi           # macOS
\`\`\`

## Version Information

- NSIS Version: $NSIS_VERSION
- Branch/Tag: $NSIS_BRANCH
- Build Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

## Included Plugins

This bundle includes 10 additional community plugins:

1. INetC - HTTP/HTTPS download plugin
2. StdUtils - Standard utilities (strings, math, system)
3. SpiderBanner - Animated splash/banner
4. NsProcess - Process management (list, kill)
5. UAC - User Account Control elevation
6. WinShell - Shell integration (file associations, shortcuts)
7. EmbedHTML - Embed HTML pages in installer
8. Nsisunz - ZIP extraction (ANSI)
9. NSISunzU - ZIP extraction (Unicode)
10. nsis7z - 7-Zip extraction

## Environment Variables

- **NSISDIR**: Path to NSIS data directory (auto-set by wrapper)
- Set manually if needed: \`export NSISDIR=/path/to/windows\`

## More Information

- NSIS Documentation: https://nsis.sourceforge.io/Docs/
- Plugin Repository: https://nsis.sourceforge.io/Category:Plugins
EOF

echo "  ✓ README created"

# =============================================================================
# Update VERSION.txt
# =============================================================================

echo ""
echo "📝 Updating VERSION.txt..."

cat > "$BUILD_DIR/nsis-bundle/VERSION.txt" <<EOF
NSIS Complete Bundle
====================
NSIS Version: $NSIS_VERSION
Branch/Tag: $NSIS_BRANCH
Bundle Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

echo "  ✓ VERSION.txt updated"

# =============================================================================
# Download NSIS License
# =============================================================================

echo ""
echo "📄 Downloading NSIS LICENSE..."
curl -fsSL --retry 3 --retry-delay 2 --max-time 60 \
  "https://raw.githubusercontent.com/NSIS-Dev/nsis/${NSIS_BRANCH}/COPYING" \
  -o "$BUILD_DIR/nsis-bundle/LICENSE"
echo "  ✓ LICENSE downloaded"

# =============================================================================
# Create Final Archive
# =============================================================================

echo ""
echo "📦 Creating final tar.gz archive..."

ARCHIVE_NAME="nsis-bundle-$NSIS_VERSION.tar.gz"
rm -f "$OUT_DIR/$ARCHIVE_NAME"

(
    cd "$BUILD_DIR"
    tar -czf "$OUT_DIR/$ARCHIVE_NAME" nsis-bundle
)

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "================================================================"
echo "  ✅ Bundle Combination Complete!"
echo "================================================================"
echo "  📁 Archive: $OUT_DIR/$ARCHIVE_NAME"
echo "  📊 Size:    $(du -h "$OUT_DIR/$ARCHIVE_NAME" | cut -f1)"
echo "================================================================"
echo ""

# =============================================================================
# Cleanup
# =============================================================================

rm -rf "$BUILD_DIR"

echo "✅ Done!"
echo ""