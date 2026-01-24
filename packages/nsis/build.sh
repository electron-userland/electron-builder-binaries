#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Main Build Script - Cross-Platform NSIS Builder
# =============================================================================
# Orchestrates building NSIS bundles for all platforms
#
# Build order:
#   1. Base (Windows) - Downloads official NSIS with all data files
#   2. Linux         - Compiles native Linux binary, injects into base
#   3. macOS         - Compiles native macOS binary, injects into base
#
# Each platform can be built independently, but they all require the base.
# =============================================================================

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ASSETS_DIR="$SCRIPT_DIR/assets"
OUT_DIR="$SCRIPT_DIR/out"

# Build configuration
export NSIS_VERSION="3.11"
export NSIS_BRANCH_OR_COMMIT="v311"
export NSIS_SHA256="c7d27f780ddb6cffb4730138cd1591e841f4b7edb155856901cdf5f214394fa1"
export STRLEN_SHA256="b1025ccf412a8662fb9a61c661370a8cfdc0da675b0c541ad0c27c2b615833ec"

# Detect current OS
OS_TYPE=${TARGET:-$(uname -s | tr '[:upper:]' '[:lower:]')}
case "$OS_TYPE" in
    darwin*) CURRENT_OS="mac" ;;
    linux*)  CURRENT_OS="linux" ;;
    *) CURRENT_OS="all" ;;
esac

BUILD_TARGET="${1:-}"

# =============================================================================
# Functions
# =============================================================================

print_banner() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  NSIS Cross-Platform Builder"
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Version:    $NSIS_VERSION ($NSIS_BRANCH_OR_COMMIT)"
    echo "  Current OS: $CURRENT_OS"
    echo "  Target:     ${BUILD_TARGET:-default}"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
}

build_base() {
    echo "📦 Building base bundle (Windows + plugins)..."
    echo ""
    bash "$ASSETS_DIR/nsis-windows.sh"
}

build_linux() {
    echo "🐧 Building Linux binary..."
    echo ""
    bash "$ASSETS_DIR/nsis-linux.sh"
}

build_mac() {
    echo "🍎 Building macOS binary..."
    echo ""
    bash "$ASSETS_DIR/nsis-mac.sh"
}

build_all() {
    echo "🌍 Building all available platforms..."
    echo ""
    build_base
    build_mac
    build_linux
    combine
}

combine() {
    echo "🔗 Combining builds..."
    echo ""
    bash "$ASSETS_DIR/nsis-combine.sh"
}

show_usage() {
    cat << EOF
Usage: $0 [TARGET]

Targets:
  base      Build base bundle (Windows + plugins + data files)
  linux     Build Linux native binary (requires Docker)
  mac       Build macOS native binary (requires macOS)
  all       Build base + current platform binary
  
  If no target specified, builds 'all'

Examples:
  ./build.sh              # Build base + current platform
  ./build.sh base         # Build only the base bundle
  ./build.sh linux        # Build Linux binary (requires Docker, builds base if needed)
  ./build.sh mac          # Build macOS binary (requires macOS, builds base if needed)
  
Platform Requirements:
  Base:   Any OS with bash, curl, unzip
  Linux:  Docker (can run on any OS)
  macOS:  Must run on macOS with Xcode Command Line Tools

EOF
}

# =============================================================================
# Main
# =============================================================================

# Handle help
if [ "$BUILD_TARGET" = "-h" ] || [ "$BUILD_TARGET" = "--help" ]; then
    show_usage
    exit 0
fi

# Print banner
print_banner

# Execute build
case "$BUILD_TARGET" in
    ""|all)
        build_all
        ;;
    base|windows|win)
        build_base
        ;;
    linux)
        build_linux
        ;;
    mac|macos|darwin)
        build_mac
        ;;
    combine)
        combine
        ;;
    *)
        echo "❌ Unknown target: $BUILD_TARGET"
        echo ""
        show_usage
        exit 1
        ;;
esac

echo ""
echo "✅ Build complete!"
echo ""