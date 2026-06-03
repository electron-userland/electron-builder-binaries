#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 7-Zip Bundle Builder
# =============================================================================
# Downloads official 7-Zip binaries for all platforms and packages each as a
# self-contained tar.gz archive for use with electron-builder's toolset
# download infrastructure.
#
# Targets:
#   all            Build all platform bundles, then test (default)
#   linux          Build Linux bundles only (x64, arm64, ia32)
#   darwin         Build macOS bundles only (arm64, x86_64)
#   win            Build Windows bundles only (x64, arm64, ia32)
#   test           Extract built bundles and run the test suite
# =============================================================================

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ASSETS_DIR="$SCRIPT_DIR/assets"

SEVEN_ZIP_VERSION="${SEVEN_ZIP_VERSION:-24.09}"
OUT_DIR="${OUT_DIR:-$SCRIPT_DIR/out/7zip}"
BUILD_TARGET=""
PRINT_DOWNLOADS_CHECKSUM=""

# =============================================================================
# Functions
# =============================================================================

print_banner() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  7-Zip Bundle Builder"
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Version: ${SEVEN_ZIP_VERSION}"
    echo "  Target:  ${BUILD_TARGET:-all}"
    echo "  Output:  ${OUT_DIR}"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
}

show_usage() {
    cat << EOF
Usage: $0 [--version VERSION] [--target TARGET] [--output-dir DIR] [--print-downloads-checksum]

Options:
  --version, -v VERSION        7-Zip version to package (default: 24.09)
  --output-dir, -o DIR         Output directory (default: ./out/7zip)
  --target, -t TARGET          Build target (default: all)
  --print-downloads-checksum   Print SHA-256 of each upstream download at the end,
                               formatted as ready-to-paste const declarations for build.js
  --help, -h                   Show this help

Targets:
  all      Build all platform bundles, then run tests (default)
  build    Build all platform bundles only — no host-level test run (used by CI)
  linux    Build Linux bundles only (x64, arm64, ia32)
  darwin   Build macOS bundles only (arm64, x86_64)
  win      Build Windows bundles only (x64, arm64, ia32)
  test     Extract built bundles and run the test suite

Environment:
  SEVEN_ZIP_VERSION   Fallback version if --version is not supplied

Examples:
  ./build.sh                                              # Build all platforms + test
  ./build.sh --version 24.09 --target linux               # Linux bundles only
  ./build.sh --target darwin                              # macOS bundles only
  ./build.sh --target test                                # Test already-built bundles
  ./build.sh --print-downloads-checksum                   # Build + print upstream checksums
EOF
}

run_docker() {
    local target="$1"
    docker run --rm \
        --volume "${ASSETS_DIR}:/assets:ro" \
        --volume "${OUT_DIR}:/output" \
        node:lts-bookworm-slim \
        node /assets/build.js \
            --version "${SEVEN_ZIP_VERSION}" \
            --output-dir /output \
            --target "${target}" \
            ${PRINT_DOWNLOADS_CHECKSUM:+--print-downloads-checksum}
}

build_linux() {
    echo "🐧 Building Linux 7-Zip bundles (Docker)..."
    run_docker linux
}

build_darwin() {
    echo "🍎 Building macOS 7-Zip bundles (Docker)..."
    run_docker darwin
}

build_win() {
    echo "🪟 Building Windows 7-Zip bundles (Docker)..."
    run_docker win
}

build_all() {
    echo "🏗️  Building all platform bundles (Docker)..."
    run_docker all
}

run_tests() {
    echo "🧪 Running 7-Zip bundle tests..."
    echo ""

    local test_base="$SCRIPT_DIR/build/test-run-$$"
    mkdir -p "$test_base"
    # Expand test_base NOW (double quotes) so the trap works after this function returns
    trap "rm -rf '${test_base}'" EXIT

    local fail=0
    for archive in "${OUT_DIR}"/*.tar.gz; do
        [[ -f "$archive" ]] || continue
        local name
        name="$(basename "$archive" .tar.gz)"

        local platform="linux"
        [[ "$name" == *"-darwin-"* ]] && platform="darwin"
        [[ "$name" == *"-win-"* ]]    && platform="win"

        local extract_dir="${test_base}/${name}"
        mkdir -p "$extract_dir"
        tar -xzf "$archive" -C "$extract_dir" --strip-components=1

        echo "── Testing ${name} ──"
        if bash "${ASSETS_DIR}/test.sh" \
                --bundle-dir "$extract_dir" \
                --platform "$platform"; then
            echo "  ✅ ${name}"
        else
            echo "  ❌ ${name}"
            fail=$((fail + 1))
        fi
        echo ""
    done

    if [[ $fail -gt 0 ]]; then
        echo "❌ ${fail} bundle(s) failed tests"
        exit 1
    fi
    echo "✅ All bundles passed"
}

# =============================================================================
# Argument parsing
# =============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version|-v)
            if [[ $# -lt 2 || -z "${2:-}" ]]; then
                echo "❌ --version requires a value"; echo ""; show_usage; exit 1
            fi
            SEVEN_ZIP_VERSION="$2"; shift 2 ;;
        --output-dir|-o)
            if [[ $# -lt 2 || -z "${2:-}" ]]; then
                echo "❌ --output-dir requires a value"; echo ""; show_usage; exit 1
            fi
            OUT_DIR="$2"; shift 2 ;;
        --target|-t)
            if [[ $# -lt 2 || -z "${2:-}" ]]; then
                echo "❌ --target requires a value"; echo ""; show_usage; exit 1
            fi
            BUILD_TARGET="$2"; shift 2 ;;
        --print-downloads-checksum) PRINT_DOWNLOADS_CHECKSUM=1; shift ;;
        --help|-h) show_usage; exit 0 ;;
        *) echo "❌ Unknown option: $1"; echo ""; show_usage; exit 1 ;;
    esac
done

# =============================================================================
# Main
# =============================================================================

print_banner

case "$BUILD_TARGET" in
    ""|all)
        rm -rf "$OUT_DIR"
        mkdir -p "$OUT_DIR"
        build_all
        run_tests
        ;;
    build)
        rm -rf "$OUT_DIR"
        mkdir -p "$OUT_DIR"
        build_all
        ;;
    linux)
        rm -rf "$OUT_DIR"
        mkdir -p "$OUT_DIR"
        build_linux
        ;;
    darwin)
        rm -rf "$OUT_DIR"
        mkdir -p "$OUT_DIR"
        build_darwin
        ;;
    win)
        rm -rf "$OUT_DIR"
        mkdir -p "$OUT_DIR"
        build_win
        ;;
    test)
        mkdir -p "$OUT_DIR"
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
