#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# WiX Toolset Bundle Builder
# =============================================================================
# Builds WiX v4 from source (wixtoolset/wix) and packages into a tar.gz.
# Source compilation is always free under MS-RL (fee applies only to the
# official pre-built binary releases). See OSMFEULA.txt in the source repo.
#
# Build order:
#   1. build        - Compile WiX from source (Windows only — requires MSVC + .NET SDK)
#   2. test-mac     - Smoke test on macOS via native Wine
#   3. test-linux   - Smoke test inside linux/amd64 Docker container via Wine
#   4. test-all     - Run test-mac and test-linux
#   5. all          - build + test-linux (CI default)
#
# Platform requirements:
#   build:       windows-2025 GitHub Actions runner (Visual Studio + MSVC + .NET SDK)
#   test-mac:    wine in PATH (brew install wine-stable)
#   test-linux:  Docker
# =============================================================================

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ASSETS_DIR="$SCRIPT_DIR/assets"
OUT_DIR="$SCRIPT_DIR/out/wix"

WIX_VERSION="4.0.6"
WIX_TAG="v4.0.6"
WIX_REPO="https://github.com/wixtoolset/wix.git"
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
    echo "Building WiX ${WIX_VERSION} from source..."
    echo ""

    # This target requires Windows — Visual Studio C++ tools and .NET SDK must be present.
    # On GitHub Actions, use the windows-2025 runner which has VS 2026 pre-installed.
    if [[ "${RUNNER_OS:-}" != "Windows" ]] && [[ "${OS:-}" != "Windows_NT" ]]; then
        echo "❌ --target build requires a Windows environment."
        echo "   WiX v4 source compilation needs Visual Studio C++ tools (wixnative.exe)"
        echo "   and the .NET SDK. Use the windows-2025 GitHub Actions runner."
        echo ""
        echo "   To test an existing artifact: --target test-mac or --target test-linux"
        exit 1
    fi

    local SRC_DIR
    SRC_DIR="$(mktemp -d)"

    mkdir -p "$OUT_DIR"

    echo "  Cloning wixtoolset/wix ${WIX_TAG}..."
    git clone --depth=1 --branch "$WIX_TAG" "$WIX_REPO" "$SRC_DIR/wix"

    # WiX generates its global.json from this template during build_init.cmd.
    # The template's "sdk" block only sets allowPrerelease:false with NO version
    # pin, so .NET picks the highest installed SDK (10.x on the runner). .NET SDK
    # 10 requires MSBuild 18, but the v143 C++ toolset WiX needs only ships with
    # VS 2022 (MSBuild 17). Pin the SDK to 8.x so MSBuild 17 can load it. This
    # preserves the template's msbuild-sdks pins (Traversal, NoTargets).
    echo "  Pinning .NET SDK to 8.x in global.json template..."
    local GLOBAL_JSON_PP="$SRC_DIR/wix/src/internal/SetBuildNumber/global.json.pp"
    sed -i.bak 's/"allowPrerelease": false/"version": "8.0.100",\n    "rollForward": "latestFeature",\n    "allowPrerelease": false/' \
        "$GLOBAL_JSON_PP"

    # Pre-create wixnative intermediate directories to avoid RC1109 on windows-2022:
    # parallel MSBuild sometimes invokes RC.exe before the IntDir exists, which
    # causes "fatal error RC1109: error creating ver.res" and silently drops the
    # wix.*.nupkg without aborting build_all.cmd.
    mkdir -p "$SRC_DIR/wix/build/wix/obj/wixnative/Release/x86"
    mkdir -p "$SRC_DIR/wix/build/wix/obj/wixnative/Release/x64"
    mkdir -p "$SRC_DIR/wix/build/wix/obj/wixnative/Release/ARM64"

    echo "  Building from source (Release, tests disabled)..."
    cd "$SRC_DIR/wix"
    export RuntimeTestsEnabled=false
    # .NET SDK 8.0.400+ promotes targeting net6.0 from a warning to a build error
    # (NETSDK1138). WiX v4.0.6's wix.csproj targets net6.0; disable the EOL check.
    export CheckEolTargetFramework=false
    # Use build_all.cmd directly to avoid the signing step in build_official.cmd.
    # On windows-2022, build_all.cmd's vswhere -version [17.0,18.0) finds VS 2022
    # and initializes the v143 developer environment automatically.
    # set +e so cmd.exe exit codes aren't silently swallowed by Git Bash under set -e.
    set +e
    cmd //c "src\\build_all.cmd" Release
    local BUILD_RC=$?
    set -e
    if [ $BUILD_RC -ne 0 ]; then
        echo "❌ build_all.cmd failed with exit code $BUILD_RC"
        exit $BUILD_RC
    fi

    echo "  Locating nupkg artifact..."
    local NUPKG
    # grep -v on empty input exits 1, which with pipefail kills the script before
    # the diagnostic below runs.  Use find's own filter and || true instead.
    NUPKG="$(find "$SRC_DIR/wix/build/artifacts" -name "wix.*.nupkg" \
        ! -name "*.symbols.nupkg" 2>/dev/null | head -1 || true)"
    if [ -z "$NUPKG" ]; then
        echo "❌ wix.*.nupkg not found in build/artifacts/ — listing contents:"
        find "$SRC_DIR/wix/build/artifacts" -type f 2>/dev/null | head -30 || true
        exit 1
    fi
    echo "  Found: $(basename "$NUPKG")"

    echo "  Extracting bundle contents from nupkg..."
    local EXTRACT_DIR="$SRC_DIR/extract"
    mkdir -p "$EXTRACT_DIR"
    # nupkg is a zip; extract everything — unzip's * doesn't cross /, so a
    # pattern like "tools/net6.0/any/*" silently drops runtimes/ and cubes/.
    # The archive is built from CONTENT_DIR so NuGet metadata is never included.
    unzip -q "$NUPKG" -d "$EXTRACT_DIR"

    local CONTENT_DIR="$EXTRACT_DIR/tools/net6.0/any"
    if [ ! -d "$CONTENT_DIR" ]; then
        echo "❌ Expected tools/net6.0/any/ inside nupkg"
        exit 1
    fi

    # Include the license (required by MS-RL for redistribution)
    cp "$SRC_DIR/wix/LICENSE.TXT" "$CONTENT_DIR/"

    echo "  Creating archive..."
    (cd "$CONTENT_DIR" && tar -czf "$OUT_DIR/$ARCHIVE_NAME" .)

    echo ""
    echo "  Done: $OUT_DIR/$ARCHIVE_NAME ($(du -h "$OUT_DIR/$ARCHIVE_NAME" | cut -f1))"

    rm -rf "$SRC_DIR"
}

test_mac() {
    echo "Running smoke test (macOS native)..."
    echo ""

    if ! command -v wine &>/dev/null; then
        echo "❌ wine not found. Install via: brew install wine-stable"
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
  build       Compile WiX v${WIX_VERSION} from source and produce the tar.gz artifact
              Requires Windows (windows-2025 GitHub Actions runner)
  test-mac    Smoke test on macOS using native Wine (brew install wine-stable)
  test-linux  Build linux/amd64 Docker image and smoke test via Wine
  test-all    Run test-mac and test-linux
  all         build + test-linux (default, matches CI)

Examples:
  ./build.sh                       # Full pipeline (Windows CI)
  ./build.sh --target build        # Compile artifact only (Windows required)
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
