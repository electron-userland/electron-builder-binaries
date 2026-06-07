#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Icons Toolset — Asset Build Script
# =============================================================================
# Bundles the icon-tool.js CLI and resvg.wasm artifact, then runs e2e tests.
#
# Targets:
#   build   Install deps, bundle CLI + wasm, create tar.gz archive
#   test    Install deps, bundle e2e runner, run e2e tests
#   all     build + test (default)
# =============================================================================

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PACKAGE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(cd "$PACKAGE_DIR/../.." && pwd)
OUT_DIR="$PACKAGE_DIR/out/icons"
BUNDLE_DIR="$PACKAGE_DIR/out/icons-bundle"
ESBUILD="$REPO_ROOT/node_modules/.bin/esbuild"
VERSION="${ICONS_VERSION:-$(node -p "require('$PACKAGE_DIR/package.json').version" 2>/dev/null || echo '1.0.0')}"

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

install_deps() {
    echo "Installing workspace dependencies..."
    cd "$PACKAGE_DIR"
    pnpm install
}

do_build() {
    echo ""
    echo "─── Bundle icon-tool.js ────────────────────────────────────────"
    mkdir -p "$OUT_DIR" "$BUNDLE_DIR"

    cd "$SCRIPT_DIR"
    "$ESBUILD" src/cli.ts \
        --bundle \
        --platform=node \
        --target=node14 \
        --format=cjs \
        --banner:js='var UZIP;' \
        --outfile="$BUNDLE_DIR/icon-tool.js"
    echo "  ✓ icon-tool.js bundled"

    echo ""
    echo "─── Copy resvg.wasm ────────────────────────────────────────────"
    local wasm_path="$PACKAGE_DIR/node_modules/@resvg/resvg-wasm/index_bg.wasm"
    if [ ! -f "$wasm_path" ]; then
        echo "ERROR: Could not locate @resvg/resvg-wasm/index_bg.wasm — is the package installed?"
        exit 1
    fi
    cp "$wasm_path" "$BUNDLE_DIR/resvg.wasm"
    echo "  ✓ resvg.wasm copied ($(du -h "$BUNDLE_DIR/resvg.wasm" | cut -f1))"

    echo ""
    echo "─── Copy vips.wasm ─────────────────────────────────────────────"
    local vips_wasm_path="$PACKAGE_DIR/node_modules/wasm-vips/lib/vips.wasm"
    if [ ! -f "$vips_wasm_path" ]; then
        echo "ERROR: Could not locate wasm-vips/lib/vips.wasm — is the package installed?"
        exit 1
    fi
    cp "$vips_wasm_path" "$BUNDLE_DIR/vips.wasm"
    echo "  ✓ vips.wasm copied ($(du -h "$BUNDLE_DIR/vips.wasm" | cut -f1))"

    echo ""
    echo "─── Create tar.gz archive ──────────────────────────────────────"
    local archive_name="icons-bundle.tar.gz"
    (
        cd "$PACKAGE_DIR/out"
        tar -czf "$OUT_DIR/$archive_name" icons-bundle
    )
    echo "  ✓ Archive: $OUT_DIR/$archive_name ($(du -h "$OUT_DIR/$archive_name" | cut -f1))"
}

do_test() {
    echo ""
    echo "─── Bundle e2e test runner ─────────────────────────────────────"
    cd "$SCRIPT_DIR"
    # validate.ts is imported by e2e.ts and bundled inline
    "$ESBUILD" tests/e2e.ts \
        --bundle \
        --platform=node \
        --target=node14 \
        --format=cjs \
        --banner:js='var UZIP;' \
        --outfile="$BUNDLE_DIR/e2e.js"
    echo "  ✓ e2e.js bundled"

    echo ""
    echo "─── Run e2e tests ──────────────────────────────────────────────"
    node "$BUNDLE_DIR/e2e.js"
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

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Icons Toolset Builder"
echo "═══════════════════════════════════════════════════════════════"
echo "  Version: $VERSION"
echo "  Target:  $BUILD_TARGET"
echo "═══════════════════════════════════════════════════════════════"

case "$BUILD_TARGET" in
    build)
        install_deps
        do_build
        ;;
    test)
        install_deps
        do_test
        ;;
    all)
        install_deps
        do_build
        do_test
        ;;
    *)
        echo "ERROR: Unknown target: $BUILD_TARGET"
        echo ""
        show_usage
        exit 1 ;;
esac

echo ""
echo "✅ Done ($BUILD_TARGET)"
echo ""
