#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# NSIS Bundle Combiner
# =============================================================================
# Combines base, Linux, macOS, and elevate bundles into a complete bundle and
# generates the universal entrypoint wrapper scripts. Writes two archives:
#   nsis-bundle-<version>.tar.gz      default: makensis + stubs with NSIS_CONFIG_LOG=no
#   nsis-bundle-<version>-log.tar.gz  makensis + stubs with NSIS_CONFIG_LOG=yes (LogSet,
#                                     electron-builder's nsis.installerDebugLogging)
# Every input archive carries the logging build under nsis-bundle/ and the
# non-logging makensis / stubs under nsis-nolog/; all other files are shared.
# =============================================================================

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
OUT_DIR="${OUT_DIR:-$BASE_DIR/out/nsis}"
BUILD_DIR="$(mktemp -d)"

# Version info
NSIS_VERSION=${NSIS_VERSION:-3.13}
NSIS_BRANCH=${NSIS_BRANCH_OR_COMMIT:-v313}

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
ELEVATE_BUNDLE=$(find "$OUT_DIR" -name "nsis-bundle-elevate-*.tar.gz" -type f | head -1)
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

if [ -z "$ELEVATE_BUNDLE" ] || [ ! -f "$ELEVATE_BUNDLE" ]; then
    echo "❌ Elevate bundle not found in $OUT_DIR"
    exit 1
fi
echo "  ✓ Elevate:      $(basename "$ELEVATE_BUNDLE")"

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
if [ ! -d "$BUILD_DIR/nsis-nolog/windows" ]; then
    echo "❌ Base bundle extraction failed - nsis-nolog/windows (non-logging makensis.exe + stubs) not found"
    exit 1
fi

echo "  ✓ Base bundle extracted"

# =============================================================================
# Inject elevate.exe
# =============================================================================

echo ""
echo "⬆️  Injecting elevate.exe..."
TEMP_ELEVATE="$BUILD_DIR/temp-elevate"
mkdir -p "$TEMP_ELEVATE"
tar -xzf "$ELEVATE_BUNDLE" -C "$TEMP_ELEVATE"
if [ ! -f "$TEMP_ELEVATE/nsis-bundle/elevate.exe" ]; then
    echo "❌ elevate.exe not found at expected path in bundle: $TEMP_ELEVATE/nsis-bundle/elevate.exe"
    exit 1
fi
cp "$TEMP_ELEVATE/nsis-bundle/elevate.exe" "$BUILD_DIR/nsis-bundle/elevate.exe"
if [ ! -d "$TEMP_ELEVATE/nsis-bundle/LICENSES/elevate" ]; then
    echo "❌ elevate license files not found in bundle: $TEMP_ELEVATE/nsis-bundle/LICENSES/elevate"
    exit 1
fi
mkdir -p "$BUILD_DIR/nsis-bundle/LICENSES"
cp -R "$TEMP_ELEVATE/nsis-bundle/LICENSES/elevate" "$BUILD_DIR/nsis-bundle/LICENSES/"
rm -rf "$TEMP_ELEVATE" "$ELEVATE_BUNDLE"
echo "  ✓ elevate.exe (and its license files) injected"

# =============================================================================
# Inject Linux Binary
# =============================================================================

if [ -n "$LINUX_BUNDLE" ]; then
    echo ""
    echo "🐧 Injecting Linux binary..."
    
    TEMP_LINUX="$BUILD_DIR/temp-linux"
    mkdir -p "$TEMP_LINUX"
    
    tar -xzf "$LINUX_BUNDLE" -C "$TEMP_LINUX"
    
    if [ -d "$TEMP_LINUX/nsis-bundle/linux" ] && [ -d "$TEMP_LINUX/nsis-nolog/linux" ]; then
        cp -r "$TEMP_LINUX/nsis-bundle/linux" "$BUILD_DIR/nsis-bundle/"
        cp -r "$TEMP_LINUX/nsis-nolog/linux" "$BUILD_DIR/nsis-nolog/"
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
        
        if [ -d "$TEMP_MAC/nsis-bundle/mac" ] && [ -f "$TEMP_MAC/nsis-nolog/mac/makensis" ]; then
            arch="${mac_bundle##*-mac-}"
            arch="${arch%%-*}"
            mkdir -p "$BUILD_DIR/nsis-bundle/mac/$arch" "$BUILD_DIR/nsis-nolog/mac/$arch"
            cp "$TEMP_MAC/nsis-bundle/mac"/* "$BUILD_DIR/nsis-bundle/mac/$arch"
            cp "$TEMP_MAC/nsis-nolog/mac/makensis" "$BUILD_DIR/nsis-nolog/mac/$arch/makensis"
            echo "  ✓ macOS binary added ($(basename "$mac_bundle"))"
        else
            echo "  ⚠️  macOS binary not found in $(basename "$mac_bundle")"
            exit 1
        fi
        
        rm -rf "$TEMP_MAC" "$mac_bundle"
    done
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
case "$UNAME_S" in
  Darwin)
    case "$ARCH" in
      x86_64) ARCH_DIR="x64" ;;
      arm64)  ARCH_DIR="arm64" ;;
      *) echo "❌ Unsupported architecture: $UNAME_M" >&2; exit 1 ;;
    esac
    BINARY="$SCRIPT_DIR/mac/$ARCH_DIR/makensis"
    ;;
  Linux)
    case "$ARCH" in
      x86_64) ARCH_DIR="x64" ;;
      arm64)  ARCH_DIR="arm64" ;;
      *) echo "❌ Unsupported architecture: $UNAME_M" >&2; exit 1 ;;
    esac
    BINARY="$SCRIPT_DIR/linux/$ARCH_DIR/makensis"
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

export NSISDIR="$SCRIPT_DIR/windows"

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

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "NSISDIR=%SCRIPT_DIR%\windows"
set "MAKENSIS_EXE=%NSISDIR%\makensis.exe"

if not exist "%MAKENSIS_EXE%" (
    echo makensis.exe not found at: %MAKENSIS_EXE% 1>&2
    exit /b 1
)

"%MAKENSIS_EXE%" %*
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

- **Windows**: \`windows/makensis.exe\` (compiled from source via Docker + MinGW-w64)
- **Linux**: \`linux/x64/makensis\` and \`linux/arm64/makensis\` (native ELF binaries, compiled from source)
- **macOS**: \`mac/makensis\` (native Mach-O binary, compiled from source)
- **Elevate**: \`elevate.exe\` (Windows privilege elevation utility, compiled from source)
- **NSIS Data**: \`windows/\` (Contrib, Include, Plugins, Stubs)
- **Universal Wrapper**: \`makensis\` (auto-detects platform, sets \`NSISDIR\`) [.cmd and .ps1 versions for Windows]
- **Licenses**: \`LICENSE\` (NSIS, including its own plugins) and \`LICENSES/\` (each community plugin and elevate.exe; see \`LICENSES/README.md\`)

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
./linux/x64/makensis your-script.nsi     # Linux x64
./linux/arm64/makensis your-script.nsi   # Linux arm64
./mac/makensis your-script.nsi           # macOS
\`\`\`

## Logging

NSIS is published as two bundles that differ only in \`makensis\` and the stubs:

- \`nsis-bundle-<version>.tar.gz\` (default): built with \`NSIS_CONFIG_LOG=no\`
- \`nsis-bundle-<version>-log.tar.gz\`: built with \`NSIS_CONFIG_LOG=yes\`, so scripts can use \`LogSet\` / \`LogText\`

The \`Logging:\` line of \`VERSION.txt\` says which bundle this is.

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

echo "🔍 Checking every plugin DLL has license terms..."
bash "$SCRIPT_DIR/nsis-plugin-licenses.sh" verify "$BUILD_DIR/nsis-bundle"

# =============================================================================
# Create the default (non-logging) and -log bundles
# =============================================================================

echo ""
echo "🪵 Creating the default (NSIS_CONFIG_LOG=no) and -log (NSIS_CONFIG_LOG=yes) bundles..."

LOG_ROOT="$BUILD_DIR/log"
DEFAULT_ROOT="$BUILD_DIR/default"
mkdir -p "$LOG_ROOT" "$DEFAULT_ROOT"
mv "$BUILD_DIR/nsis-bundle" "$LOG_ROOT/nsis-bundle"
cp -a "$LOG_ROOT/nsis-bundle" "$DEFAULT_ROOT/nsis-bundle"

# Every makensis of the bundle needs its non-logging build, and the two stub sets must have the same files
while IFS= read -r rel; do
    if [ ! -f "$BUILD_DIR/nsis-nolog/$rel" ]; then
        echo "❌ no non-logging build of $rel"
        exit 1
    fi
done < <(cd "$LOG_ROOT/nsis-bundle" && find windows/makensis.exe linux mac -type f -name 'makensis*' 2>/dev/null)
if ! diff <(cd "$LOG_ROOT/nsis-bundle/windows/Stubs" && find . -type f | sort) <(cd "$BUILD_DIR/nsis-nolog/windows/Stubs" && find . -type f | sort); then
    echo "❌ the logging and non-logging builds have different stubs"
    exit 1
fi
while IFS= read -r rel; do
    if [ ! -f "$LOG_ROOT/nsis-bundle/$rel" ]; then
        echo "❌ non-logging $rel has no counterpart in the logging bundle"
        exit 1
    fi
    cp "$BUILD_DIR/nsis-nolog/$rel" "$DEFAULT_ROOT/nsis-bundle/$rel"
done < <(cd "$BUILD_DIR/nsis-nolog" && find . -type f | sed 's|^\./||')
rm -rf "$BUILD_DIR/nsis-nolog"

# Platform VERSION.txt files describe the logging build; rewrite them for the default bundle (portable sed, no -i)
rewrite() {
    local file="$1"; shift
    sed "$@" "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}
rewrite "$DEFAULT_ROOT/nsis-bundle/windows/VERSION.txt" -e 's/(LOG + STRLEN=8192)/(STRLEN=8192)/' -e 's/^Log Feature: enabled/Log Feature: disabled/'
while IFS= read -r version_file; do
    rewrite "$version_file" -e 's/NSIS_CONFIG_LOG=yes (matches the Windows stubs)/NSIS_CONFIG_LOG=no (matches the Windows stubs)/'
done < <(find "$DEFAULT_ROOT/nsis-bundle/linux" "$DEFAULT_ROOT/nsis-bundle/mac" -name VERSION.txt 2>/dev/null)
echo "Logging: NSIS_CONFIG_LOG=no (LogSet unsupported; use the -log bundle for logging)" >> "$DEFAULT_ROOT/nsis-bundle/VERSION.txt"
echo "Logging: NSIS_CONFIG_LOG=yes (makensis and stubs)" >> "$LOG_ROOT/nsis-bundle/VERSION.txt"

# The bundles may differ only in the makensis builds, the stubs and the VERSION.txt files
UNEXPECTED_DIFF=$(diff -rq "$LOG_ROOT/nsis-bundle" "$DEFAULT_ROOT/nsis-bundle" \
    | sed -e "s|$LOG_ROOT/nsis-bundle/||" -e "s| and .*||" -e 's|^Files ||' \
    | grep -vE '^(windows/makensis\.exe|linux/[^/]+/makensis|mac/[^/]+/makensis|windows/Stubs/[^/]+|(.+/)?VERSION\.txt)$' || true)
if [ -n "$UNEXPECTED_DIFF" ]; then
    echo "❌ the default and -log bundles differ in more than makensis / stubs:"
    echo "$UNEXPECTED_DIFF"
    exit 1
fi
echo "  ✓ default and -log bundles differ only in makensis, Stubs/ and VERSION.txt"

# =============================================================================
# Create Final Archives
# =============================================================================

echo ""
echo "📦 Creating final tar.gz archives..."

ARCHIVE_NAME="nsis-bundle-$NSIS_VERSION.tar.gz"
LOG_ARCHIVE_NAME="nsis-bundle-$NSIS_VERSION-log.tar.gz"
rm -f "$OUT_DIR/$ARCHIVE_NAME" "$OUT_DIR/$LOG_ARCHIVE_NAME"

# both archives hold a top-level nsis-bundle/ directory
(cd "$DEFAULT_ROOT" && tar -czf "$OUT_DIR/$ARCHIVE_NAME" nsis-bundle)
(cd "$LOG_ROOT" && tar -czf "$OUT_DIR/$LOG_ARCHIVE_NAME" nsis-bundle)

rm -rf "$OUT_DIR/nsis-bundle" "$OUT_DIR/nsis-bundle-log"
mv "$DEFAULT_ROOT/nsis-bundle" "$OUT_DIR/nsis-bundle"
mv "$LOG_ROOT/nsis-bundle" "$OUT_DIR/nsis-bundle-log"

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "================================================================"
echo "  ✅ Bundle Combination Complete!"
echo "================================================================"
echo "  📁 Directories: $OUT_DIR/nsis-bundle, $OUT_DIR/nsis-bundle-log"
echo "  📁 Archive:     $OUT_DIR/$ARCHIVE_NAME ($(du -h "$OUT_DIR/$ARCHIVE_NAME" | cut -f1))"
echo "  📁 Archive:     $OUT_DIR/$LOG_ARCHIVE_NAME ($(du -h "$OUT_DIR/$LOG_ARCHIVE_NAME" | cut -f1))"
echo "================================================================"
echo ""

echo "✅ Done!"
echo ""