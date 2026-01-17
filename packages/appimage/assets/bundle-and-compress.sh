#!/usr/bin/env bash
set -euo pipefail

# Root of the project (can be overridden by caller)
ROOT=$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)
OUT_DIR="${OUT_DIR:-$ROOT/out}"

BUILD_DIR="/tmp/appimage-bundle-and-compress"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUT_DIR"

# Input directory containing the zip files
ZIP_DIR="${ZIP_DIR:-$ROOT/out/build}"

tree $ZIP_DIR -L 2 2>/dev/null || find $ZIP_DIR -maxdepth 2 -type f

if [ -z "$(ls -A "$ZIP_DIR"/appimage-*.tar.gz 2>/dev/null)" ]; then
    echo "❌ No input tar.gz files found in $ZIP_DIR"
    exit 1
fi

# ----------------------------
# Runtime → project root
# ----------------------------
echo "Extracting runtime to project root → $BUILD_DIR"
tar -xzf "$ZIP_DIR"/appimage-runtime*.tar.gz -C "$BUILD_DIR"
rm -f "$ZIP_DIR"/appimage-runtime*.tar.gz

# ----------------------------
# macOS → darwin/<arch>
# ----------------------------
for zip in "$ZIP_DIR"/appimage-tools-darwin-*.tar.gz; do
    [[ -e "$zip" ]] || continue
    echo "Extracting macOS → $BUILD_DIR/darwin"
    tar -xzf "$zip" -C "$BUILD_DIR"
    rm -f "$zip"
done

# ----------------------------
# Linux (all architectures) → linux/<arch>
# ----------------------------
LINUX_ZIP="$ZIP_DIR/appimage-tools-linux-all-architectures.tar.gz"
echo "Extracting Linux (all architectures) → $BUILD_DIR/linux"
tar -xzf "$LINUX_ZIP" -C "$BUILD_DIR"
rm -f "$LINUX_ZIP"


# =============================================================================
# CREATE GENERIC APPIMAGE TOOL WRAPPER
# =============================================================================
echo ""
echo "🔨 Creating generic AppImage tool wrapper with debug support..."

cat <<'EOF' >"$BUILD_DIR/appimage-tool"
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load shared runtime selector
source "$ROOT_DIR/select-runtime.env"

# Determine tool name
INVOKED_AS="$(basename "$0")"

if [[ "$INVOKED_AS" == "appimage-tool" ]]; then
    if [[ $# -lt 1 ]]; then
        echo "Usage:"
        echo "  appimage-tool <tool-name> [args...]"
        exit 1
    fi
    TOOL_NAME="$1"
    shift
else
    TOOL_NAME="$INVOKED_AS"
fi

BIN="$APPIMAGE_TOOLS_DIR/$TOOL_NAME"

if [[ ! -x "$BIN" ]]; then
    echo "Tool not found or not executable:"
    echo "   $BIN"
    echo
    echo "Available tools:"
    ls -1 "$APPIMAGE_TOOLS_DIR" 2>/dev/null || true
    exit 1
fi

# Debug mode
if [[ "${1:-}" == "--debug" || "${1:-}" == "-d" ]]; then
    echo "=== AppImage Tool Debug Info ==="
    echo "Tool name:        $TOOL_NAME"
    echo "Binary path:      $BIN"
    echo "Platform:         $APPIMAGE_TOOLS_PLATFORM"
    echo "Architecture:     $APPIMAGE_TOOLS_ARCH"
    echo "Runtime dir:      $APPIMAGE_TOOLS_DIR"
    echo "Library dir:      $APPIMAGE_TOOLS_LIBDIR"
    if [[ "$APPIMAGE_TOOLS_PLATFORM" == "darwin" ]]; then
        echo "DYLD_LIBRARY_PATH: $DYLD_LIBRARY_PATH"
    else
        echo "LD_LIBRARY_PATH:   $LD_LIBRARY_PATH"
    fi
    echo "Executable file info:"
    file "$BIN"
    echo "Dynamic libs:"
    if [[ "$APPIMAGE_TOOLS_PLATFORM" == "darwin" ]]; then
        otool -L "$BIN" || true
    else
        ldd "$BIN" || true
    fi
    exit 0
fi

# macOS: remove quarantine attribute if present
if [[ "$APPIMAGE_TOOLS_PLATFORM" == "darwin" ]]; then
    if command -v xattr >/dev/null 2>&1; then
        xattr -dr com.apple.quarantine "$APPIMAGE_TOOLS_DIR" 2>/dev/null || true
    fi
fi

# Execute normally
exec "$BIN" "$@"
EOF
chmod +x "$BUILD_DIR/appimage-tool"

# =========================
# select-runtime.env
# =========================
echo "  ✏️  select-runtime.env"
cat <<'EOF' >"$BUILD_DIR/select-runtime.env"
#!/usr/bin/env bash
# Shared AppImage tools runtime selector

set -euo pipefail

TOOLS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set platform: "darwin" or "linux"
APPIMAGE_TOOLS_PLATFORM="$(uname -s | tr '[:upper:]' '[:lower:]')"

# Set architecture with fallback to x64
case "$(uname -m)" in
    x86_64|amd64)   APPIMAGE_TOOLS_ARCH="x64" ;;
    arm64|aarch64)  APPIMAGE_TOOLS_ARCH="arm64" ;;
    armv7l|armv6l)  APPIMAGE_TOOLS_ARCH="arm32" ;;
    i686|i386)      APPIMAGE_TOOLS_ARCH="ia32" ;;
    *)              APPIMAGE_TOOLS_ARCH="x64" ;;  # fallback
esac

APPIMAGE_TOOLS_DIR="$TOOLS_ROOT/$APPIMAGE_TOOLS_PLATFORM/$APPIMAGE_TOOLS_ARCH"
APPIMAGE_TOOLS_LIBDIR="$APPIMAGE_TOOLS_DIR/lib"

if [[ ! -d "$APPIMAGE_TOOLS_DIR" ]]; then
    echo "AppImage tools directory not found:"
    echo "   $APPIMAGE_TOOLS_DIR"
    echo "Platform: $APPIMAGE_TOOLS_PLATFORM"
    echo "Arch:     $APPIMAGE_TOOLS_ARCH"
    return 1
fi

if [[ "$APPIMAGE_TOOLS_PLATFORM" == "darwin" ]]; then
    export DYLD_LIBRARY_PATH="$APPIMAGE_TOOLS_LIBDIR${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
else
    export LD_LIBRARY_PATH="$APPIMAGE_TOOLS_LIBDIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

export APPIMAGE_TOOLS_PLATFORM
export APPIMAGE_TOOLS_ARCH
export APPIMAGE_TOOLS_DIR
export APPIMAGE_TOOLS_LIBDIR
EOF
chmod +x "$BUILD_DIR/select-runtime.env"

ENTRYPOINTS=("mksquashfs" "desktop-file-validate" "opj_decompress")
for entry in "${ENTRYPOINTS[@]}"; do
    ln -sf appimage-tool "$BUILD_DIR/$entry"
done

echo "✅ Generic AppImage tool wrapper created"

# =============================
# Create final tar.gz bundle
# =============================
echo ""
echo "📦 Creating final tar.gz archive of all AppImage tools and runtimes..."

ARCHIVE_NAME="appimage-tools-runtime-$APPIMAGE_TYPE2_RELEASE.tar.gz"
rm -f "$OUT_DIR/$ARCHIVE_NAME"
echo "📦 Creating tar.gz bundle: $ARCHIVE_NAME"
(
    cd "$BUILD_DIR"
    tar czf "$OUT_DIR/$ARCHIVE_NAME" .
)
echo "✅ Done!"
echo "Bundle at: $OUT_DIR/$ARCHIVE_NAME"

rm -rf "$BUILD_DIR"