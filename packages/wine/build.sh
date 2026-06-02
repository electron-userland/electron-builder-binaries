#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Wine Portable Bundle Builder
# =============================================================================
# Compiles Wine from source for macOS and Linux, producing a self-contained
# portable bundle for use with electron-builder.
#
# Targets:
#   mac / darwin   Build macOS x86_64 Wine bundle (native Homebrew build)
#   linux          Build Linux x86_64 Wine bundle (via Docker)
#   test / sanity  Run sanity + e2e tests against the built bundle
#   all            Build for current platform, then test (default)
# =============================================================================

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ASSETS_DIR="$SCRIPT_DIR/assets"
OUT_DIR="$SCRIPT_DIR/out"

export WINE_VERSION="${WINE_VERSION:-11.0}"
export BUILD_DIR="${BUILD_DIR:-$SCRIPT_DIR/build}"
export OUT_DIR

OS_TYPE=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$OS_TYPE" in
    darwin*) CURRENT_OS="darwin" ;;
    linux*)  CURRENT_OS="linux" ;;
    *)       CURRENT_OS="$OS_TYPE" ;;
esac

BUILD_TARGET=""

# =============================================================================
# Functions
# =============================================================================

print_banner() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Wine Portable Bundle Builder"
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Wine Version: $WINE_VERSION"
    echo "  Current OS:   $CURRENT_OS"
    echo "  Target:       ${BUILD_TARGET:-all}"
    echo "  Output:       $OUT_DIR"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
}

build_mac() {
    echo "🍎 Building macOS Wine bundle..."
    echo ""
    export OS_TARGET=darwin
    bash "$ASSETS_DIR/build-wine.sh"
}

build_linux() {
    echo "🐧 Building Linux Wine bundle (Docker)..."
    echo ""
    bash "$ASSETS_DIR/build-linux.sh"
}

run_tests() {
    echo "🧪 Running Wine sanity + e2e tests..."
    echo ""
    bash "$ASSETS_DIR/test.sh" --bundle-dir "$OUT_DIR"
}

build_current_platform() {
    case "$CURRENT_OS" in
        darwin) build_mac ;;
        linux)  build_linux ;;
        *)
            echo "❌ Unsupported OS for automatic platform detection: $CURRENT_OS"
            echo "   Use --target mac or --target linux explicitly."
            exit 1
            ;;
    esac
}

show_usage() {
    cat << EOF
Usage: $0 [--target TARGET]

Options:
  --target, -t TARGET   Build target (default: all)
  --help, -h            Show this help

Targets:
  mac, darwin    Build macOS x86_64 Wine bundle (requires macOS + Homebrew)
  linux          Build Linux x86_64 Wine bundle (requires Docker)
  test, sanity   Run sanity + e2e tests against the built bundle
  all            Build for current platform, then run tests (default)

Environment:
  WINE_VERSION   Wine version to build (default: 11.0)
  BUILD_DIR      Scratch build directory (default: ./build)

Examples:
  ./build.sh                       # Build + test for current platform
  ./build.sh --target mac          # Build macOS bundle only
  ./build.sh --target linux        # Build Linux bundle (via Docker)
  ./build.sh --target test         # Test an already-built bundle
EOF
}

# =============================================================================
# Argument parsing
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
        --help|-h) show_usage; exit 0 ;;
        *) echo "❌ Unknown option: $1"; echo ""; show_usage; exit 1 ;;
    esac
done

# =============================================================================
# Main
# =============================================================================

print_banner
mkdir -p "$BUILD_DIR" "$OUT_DIR"

case "$BUILD_TARGET" in
    ""|all)
        build_current_platform
        run_tests
        ;;
    mac|darwin)
        build_mac
        ;;
    linux)
        build_linux
        ;;
    test|sanity)
        run_tests
        ;;
    *)
        echo "❌ Unknown target: $BUILD_TARGET"
        echo ""
        show_usage
        exit 1
        ;;
esac

echo ""
echo "✅ Done!"
echo ""
