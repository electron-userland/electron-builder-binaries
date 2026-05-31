#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# WiX Toolset Bundle Builder
# =============================================================================
# Downloads the official WiX v3 release, filters to runtime-only files,
# and packages them into a tar.gz artifact.
#
# Build order:
#   1. build        - Download, verify, filter, and compress WiX binaries
#   2. test-mac     - Run smoke test natively (needs wine in PATH, e.g. via Homebrew)
#   3. test-linux   - Build linux/amd64 Docker image and run smoke test via Wine
#   4. test-all     - Run test-mac and test-linux
#   5. all          - Run build then test-linux (default, matches CI)
# =============================================================================

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ASSETS_DIR="$SCRIPT_DIR/assets"
OUT_DIR="$SCRIPT_DIR/out/wix"

WIX_VERSION="3.14.1"
WIX_TAG="wix3141rtm"
WIX_ZIP_URL="https://github.com/wixtoolset/wix3/releases/download/${WIX_TAG}/wix314-binaries.zip"
WIX_SHA256="6ac824e1642d6f7277d0ed7ea09411a508f6116ba6fae0aa5f2c7daa2ff43d31"
ARCHIVE_NAME="wix-${WIX_VERSION}.tar.gz"

DOCKER_IMAGE="wix-builder"

BUILD_TARGET=""

# =============================================================================
# Functions
# =============================================================================

print_banner() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  WiX Toolset Bundle Builder"
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Version: ${WIX_VERSION} (${WIX_TAG})"
    echo "  Target:  ${BUILD_TARGET:-all}"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
}

build_bundle() {
    echo "Downloading and packaging WiX ${WIX_VERSION}..."
    echo ""

    local BUILD_DIR
    BUILD_DIR="$(mktemp -d)"

    rm -rf "$OUT_DIR"
    mkdir -p "$OUT_DIR" "$BUILD_DIR/extract" "$BUILD_DIR/bundle"

    echo "  Downloading..."
    curl -fsSL --retry 3 "$WIX_ZIP_URL" -o "$BUILD_DIR/wix.zip"

    echo "  Verifying checksum..."
    echo "${WIX_SHA256}  $BUILD_DIR/wix.zip" | sha256sum -c -

    echo "  Extracting..."
    unzip -q "$BUILD_DIR/wix.zip" -d "$BUILD_DIR/extract"

    echo "  Filtering runtime files (excluding sdk/ and doc/)..."
    rsync -a --exclude='sdk/' --exclude='doc/' "$BUILD_DIR/extract/" "$BUILD_DIR/bundle/"

    echo "  Deleting existing output and copying bundle..."
    cp -r "$BUILD_DIR/bundle" "$OUT_DIR"

    echo "  Creating archive..."
    (cd "$OUT_DIR/bundle" && tar -czf "$OUT_DIR/$ARCHIVE_NAME" .)

    echo ""
    echo "  Done: $OUT_DIR/$ARCHIVE_NAME"
    echo "  Size: $(du -h "$OUT_DIR/$ARCHIVE_NAME" | cut -f1)"

    rm -rf "$BUILD_DIR"
}

test_mac() {
    echo "Running smoke test (macOS native)..."
    echo ""

    if ! command -v wine &>/dev/null; then
        echo "❌ wine not found in PATH. Install via: brew install wine-stable"
        exit 1
    fi

    bash "$ASSETS_DIR/test.sh"
}

test_linux() {
    echo "Running smoke test (linux/amd64 via Docker)..."
    echo ""
    docker build --platform linux/amd64 -t "$DOCKER_IMAGE" "$SCRIPT_DIR"
    docker run --rm \
        --platform linux/amd64 \
        -v "$SCRIPT_DIR:/pkg" \
        -w /pkg \
        "$DOCKER_IMAGE" \
        bash assets/test.sh
}

run_all() {
    build_bundle
    test_linux
    test_mac
}

show_usage() {
    cat << EOF
Usage: $0 [--target TARGET]

Options:
  --target, -t TARGET   Build target (default: all)
  --help, -h            Show this help

Targets:
  build       Download WiX binaries and produce the tar.gz artifact
  test-mac    Run smoke test natively (requires wine in PATH, e.g. brew install wine-stable)
  test-linux  Build linux/amd64 Docker image and run smoke test via Wine
  test-all    Run test-mac and test-linux
  all         Run build then test-linux (default)

Examples:
  ./build.sh                       # Build artifact and run Docker smoke test
  ./build.sh --target build        # Produce artifact only (no Docker/Wine)
  ./build.sh --target test-mac     # Test natively on macOS with local Wine
  ./build.sh --target test-linux   # Test inside linux/amd64 Docker container
  ./build.sh --target test-all     # Run both test-mac and test-linux

Requirements:
  build:       curl, unzip, rsync, tar, sha256sum
  test-mac:    wine (brew install wine-stable)
  test-linux:  Docker

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
        --help|-h) show_usage; exit 0 ;;
        *) echo "❌ Unknown option: $1"; echo ""; show_usage; exit 1 ;;
    esac
done

print_banner

case "$BUILD_TARGET" in
    ""|all)
        run_all
        ;;
    build)
        build_bundle
        ;;
    test-mac)
        test_mac
        ;;
    test-linux)
        test_linux
        ;;
    test-all)
        test_linux
        test_mac
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
