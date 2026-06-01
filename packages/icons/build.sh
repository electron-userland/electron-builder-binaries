#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Icons Toolset — Main Build Script
# =============================================================================
# Orchestrates building and testing the portable icons toolset.
#
# Usage:
#   ./build.sh --target build    # Bundle icon-tool.js + wasm, create archive
#   ./build.sh --target test     # Run e2e test suite (requires prior build)
#   ./build.sh --target all      # build + test (default)
# =============================================================================

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ASSETS_DIR="$SCRIPT_DIR/assets"

BUILD_TARGET="all"

# =============================================================================
# Functions
# =============================================================================

show_usage() {
    cat << EOF
Usage: $0 --target TARGET

Options:
  --target, -t TARGET   Build target (default: all)
  --help,   -h          Show this help

Targets:
  build     Bundle icon-tool.js + resvg.wasm and create tar.gz archive
  test      Run e2e test suite against the built bundle
  all       build + test (default)

Examples:
  $0 --target build    # Bundle only — skip tests
  $0 --target test     # Test only — requires a prior build
  $0 --target all      # Full build + test (CI default)

EOF
}

# =============================================================================
# Argument parsing
# =============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target|-t)
            if [[ $# -lt 2 || -z "${2:-}" ]]; then
                echo "ERROR: --target requires a value"
                echo ""
                show_usage
                exit 1
            fi
            BUILD_TARGET="$2"; shift 2 ;;
        --help|-h)
            show_usage; exit 0 ;;
        *)
            echo "ERROR: Unknown option: $1"
            echo ""
            show_usage
            exit 1 ;;
    esac
done

# =============================================================================
# Main
# =============================================================================

# Clean output directory on a fresh build (not test-only)
if [[ "$BUILD_TARGET" == "build" || "$BUILD_TARGET" == "all" ]]; then
    rm -rf "$SCRIPT_DIR/out"
fi

bash "$ASSETS_DIR/build.sh" --target "$BUILD_TARGET"
