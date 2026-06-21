#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# WiX Toolset Bundle Builder
# =============================================================================
# Downloads the official WiX v3 binaries (wixtoolset/wix3) and repackages them
# into a tar.gz. WiX v3 ships the classic candle.exe + light.exe pipeline, which
# runs under Wine/mono on macOS and Linux — this is what electron-builder needs
# for cross-platform MSI and Squirrel.Windows builds. (WiX v4's single wix.exe
# targets .NET 6 and does not run under mono.)
#
# The WiX v3 binaries are distributed under the MS-RL; LICENSE.TXT ships inside
# the upstream zip and is preserved in the bundle for redistribution.
#
# Build order:
#   1. build        - Download + repackage the v3 binaries into the tar.gz
#   2. test-mac     - Smoke test on macOS via native Wine
#   3. test-linux   - Smoke test inside linux/amd64 Docker container via Wine
#   4. test-all     - Run test-mac and test-linux
#   5. all          - build + tests (CI default)
#
# Platform requirements:
#   build:       any host with curl, unzip, rsync, tar (no compiler needed)
#   test-mac:    wine in PATH (brew install --cask wine-stable)
#   test-linux:  Docker
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

# Portable SHA-256 verification (sha256sum on Linux, shasum -a 256 on macOS).
verify_sha256() {
    local file="$1" expected="$2" actual
    if command -v sha256sum &>/dev/null; then
        actual="$(sha256sum "$file" | cut -d' ' -f1)"
    elif command -v shasum &>/dev/null; then
        actual="$(shasum -a 256 "$file" | cut -d' ' -f1)"
    else
        echo "❌ no sha256 tool found (need sha256sum or shasum)"
        exit 1
    fi
    if [ "$actual" != "$expected" ]; then
        echo "❌ checksum mismatch for $(basename "$file")"
        echo "   expected: $expected"
        echo "   actual:   $actual"
        exit 1
    fi
}

build_bundle() {
    echo "Downloading WiX ${WIX_VERSION} binaries..."
    echo ""

    local SRC_DIR
    SRC_DIR="$(mktemp -d)"

    mkdir -p "$OUT_DIR" "$SRC_DIR/extract" "$SRC_DIR/bundle"

    echo "  Fetching ${WIX_ZIP_URL}"
    curl -fsSL --retry 3 "$WIX_ZIP_URL" -o "$SRC_DIR/wix.zip"

    echo "  Verifying SHA-256..."
    verify_sha256 "$SRC_DIR/wix.zip" "$WIX_SHA256"

    echo "  Extracting..."
    unzip -q "$SRC_DIR/wix.zip" -d "$SRC_DIR/extract"

    # Strip dev-only payloads: sdk/ (libs + headers) and doc/ (chm/xsd).
    # Everything else is kept, including LICENSE.TXT (MS-RL, required for
    # redistribution), the candle/light/* tools, the Wix*Extension.dll set,
    # the ICE cubes, and x86/burn.exe.
    echo "  Filtering runtime files (excluding sdk/ and doc/)..."
    rsync -a --exclude='sdk/' --exclude='doc/' "$SRC_DIR/extract/" "$SRC_DIR/bundle/"

    if [ ! -f "$SRC_DIR/bundle/LICENSE.TXT" ]; then
        echo "❌ LICENSE.TXT missing from bundle — required by MS-RL for redistribution"
        exit 1
    fi

    echo "  Creating archive..."
    (cd "$SRC_DIR/bundle" && tar -czf "$OUT_DIR/$ARCHIVE_NAME" .)

    echo ""
    echo "  Done: $OUT_DIR/$ARCHIVE_NAME ($(du -h "$OUT_DIR/$ARCHIVE_NAME" | cut -f1))"

    rm -rf "$SRC_DIR"
}

test_mac() {
    echo "Running smoke test (macOS native)..."
    echo ""

    if ! command -v wine &>/dev/null; then
        echo "❌ wine not found. Install via: brew install --cask wine-stable"
        exit 1
    fi

    bash "$ASSETS_DIR/test.sh"
}

build_image() {
    echo "Building Docker image (linux/amd64)..."
    echo ""
    docker build --platform linux/amd64 -t "$DOCKER_IMAGE" "$SCRIPT_DIR"
}

test_linux() {
    echo "Running smoke test (linux/amd64 via Docker)..."
    echo ""
    docker run --rm \
        --platform linux/amd64 \
        -v "$SCRIPT_DIR:/pkg" \
        -w /pkg \
        "$DOCKER_IMAGE" \
        bash assets/test.sh
}

run_all() {
    build_bundle
    build_image
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
  build       Download WiX v${WIX_VERSION} binaries and produce the tar.gz artifact
              (needs curl, unzip, rsync, tar — runs on any host, no compiler)
  test-mac    Smoke test on macOS using native Wine (brew install --cask wine-stable)
  test-linux  Build linux/amd64 Docker image and smoke test via Wine
  test-all    Run test-mac and test-linux
  all         build + tests (default)

Examples:
  ./build.sh                       # Full pipeline
  ./build.sh --target build        # Produce the artifact only
  ./build.sh --target test-mac     # Test existing artifact on macOS
  ./build.sh --target test-linux   # Test existing artifact in Docker
  ./build.sh --target test-all     # Run both test targets

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
        build_image
        test_linux
        ;;
    test-all)
        build_image
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
