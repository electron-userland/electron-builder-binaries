#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Main Build Script - Cross-Platform NSIS Builder
# =============================================================================
# Orchestrates building NSIS bundles for all platforms
#
# Build order:
#   1. Base (Windows) - Compiles makensis.exe + stubs from source via Docker + MinGW
#   2. Linux         - Compiles native Linux binary via Docker (x64 + arm64)
#   3. macOS         - Compiles native macOS binary (x64 + arm64)
#
# Each platform can be built independently, but they all require the base.
# =============================================================================

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ASSETS_DIR="$SCRIPT_DIR/assets"
OUT_DIR="$SCRIPT_DIR/out"

# Build configuration
export NSIS_VERSION="3.12"
export NSIS_BRANCH_OR_COMMIT="e3f60402bcdf7be822d159b531c6e38ddf32de12"

# Detect current OS
OS_TYPE=${TARGET:-$(uname -s | tr '[:upper:]' '[:lower:]')}
case "$OS_TYPE" in
    darwin*) CURRENT_OS="mac" ;;
    linux*)  CURRENT_OS="linux" ;;
    *) CURRENT_OS="all" ;;
esac

BUILD_TARGET=""

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
    echo "📦 Building base bundle (Windows makensis from source + plugins)..."
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

build_elevate() {
    echo "⬆️  Building elevate.exe (Docker)..."
    echo ""
    bash "$ASSETS_DIR/nsis-elevate.sh"
}

build_all() {
    echo "🌍 Building all available platforms..."
    echo ""
    build_base
    build_mac
    build_linux
    build_elevate
    combine
}

combine() {
    echo "🔗 Combining builds..."
    echo ""
    bash "$ASSETS_DIR/nsis-combine.sh"
}

show_usage() {
    cat << EOF
Usage: $0 --target TARGET

Options:
  --target, -t TARGET   Build target (default: all)
  --help, -h            Show this help

Targets:
  base              Build base bundle (Windows + plugins + data files)
  windows, win      Alias for base
  linux             Build Linux native binary (requires Docker)
  mac, macos        Build macOS native binary (requires macOS)
  elevate           Build elevate.exe from source (requires Docker)
  combine           Combine previously built platform bundles into final archive
  all               Build all platforms (base + mac + linux + elevate + combine)

Examples:
  ./build.sh --target all     # Build all platforms and combine
  ./build.sh --target base    # Build only the base bundle
  ./build.sh --target linux   # Build Linux binary (requires Docker)
  ./build.sh --target mac     # Build macOS binary (requires macOS)
  ./build.sh --target combine # Combine existing platform bundles

Platform Requirements:
  Base:   Docker (can run on any OS with Docker)
  Linux:  Docker (can run on any OS with Docker)
  macOS:  Must run on macOS with Xcode Command Line Tools + scons

EOF
}

# =============================================================================
# Main
# =============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target|-t)
            if [[ $# -lt 2 || -z "${2:-}" ]]; then
                echo "❌ --target requires a value"
                echo ""
                show_usage
                exit 1
            fi
            BUILD_TARGET="$2"; shift 2 ;;
        --help|-h)   show_usage; exit 0 ;;
        *) echo "❌ Unknown option: $1"; echo ""; show_usage; exit 1 ;;
    esac
done

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
    elevate)
        build_elevate
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