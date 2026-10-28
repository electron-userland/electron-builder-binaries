#!/usr/bin/env bash
set -euo pipefail

# Root of the project (can be overridden by caller)
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT_DIR="${OUT_DIR:-$ROOT/out}"
APPIMAGE_TYPE2_RELEASE="${APPIMAGE_TYPE2_RELEASE:?APPIMAGE_TYPE2_RELEASE must be set (build.sh exports it)}"
VERIFY_LICENSES="$ROOT/../../scripts/verify-licenses.sh"
# shellcheck source=SCRIPTDIR/collect-licenses.sh
source "$ROOT/assets/collect-licenses.sh"

BUILD_DIR="/tmp/appimage-bundle-and-compress"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUT_DIR"

# Input directory containing the zip files
ZIP_DIR="${ZIP_DIR:-$ROOT/out/build}"

tree "$ZIP_DIR" -L 2 2>/dev/null || find "$ZIP_DIR" -maxdepth 2 -type f

if [ -z "$(ls -A "$ZIP_DIR"/appimage-*.tar.gz 2>/dev/null)" ]; then
    echo "❌ No input tar.gz files found in $ZIP_DIR"
    exit 1
fi

# Each input tarball is extracted on its own, its licenses checked, and then merged into BUILD_DIR: the
# LICENSES/MANIFEST.tsv files are concatenated and any file two tarballs share must be identical.
STAGING_DIR="$BUILD_DIR.staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
trap 'rm -rf "$STAGING_DIR"' EXIT

# extract_and_merge <tarball> <check licenses: 1|0>
extract_and_merge() {
    local tarball="$1" check="$2" staging
    staging="$STAGING_DIR/$(basename "$tarball" .tar.gz)"
    mkdir "$staging"
    tar -xzf "$tarball" -C "$staging"
    if [[ "$check" == 1 ]]; then
        bash "$VERIFY_LICENSES" "$staging"
    fi
    lic_merge "$BUILD_DIR" "$staging"
    rm -rf "$staging"
    rm -f "$tarball"
}

# ----------------------------
# Runtime → runtimes/ (its licenses are added below)
# ----------------------------
RUNTIME_ZIP="$ZIP_DIR/appimage-runtime-$APPIMAGE_TYPE2_RELEASE.tar.gz"
echo "Extracting runtime → $BUILD_DIR/runtimes"
extract_and_merge "$RUNTIME_ZIP" 0

# ----------------------------
# macOS → darwin/<arch>
# ----------------------------
darwin_zips=0
for zip in "$ZIP_DIR"/appimage-tools-darwin-*.tar.gz; do
    [[ -e "$zip" ]] || continue
    echo "Extracting macOS $(basename "$zip") → $BUILD_DIR/darwin"
    extract_and_merge "$zip" 1
    darwin_zips=$((darwin_zips + 1))
done
echo "   $darwin_zips macOS tarball(s) merged"

# ----------------------------
# Linux (all architectures) → linux/<arch>
# ----------------------------
LINUX_ZIP="$ZIP_DIR/appimage-tools-linux-all-architectures.tar.gz"
echo "Extracting Linux (all architectures) → $BUILD_DIR/linux"
extract_and_merge "$LINUX_ZIP" 1

# =============================================================================
# CROSS-PLATFORM MKSQUASHFS PARITY
# =============================================================================
# Every build compresses the same self-test fixture with zstd (build-appimage.sh
# squashfs_selftest). All platforms must produce the same image bytes.
echo ""
echo "🔍 Checking mksquashfs zstd output parity across platforms..."
PARITY_KEY="squashfs selftest zstd image sha256:"
parity_ref=""
parity_ok=1
parity_report=""
for version_file in "$BUILD_DIR"/{darwin,linux}/*/VERSION.txt; do
    [[ -e "$version_file" ]] || continue
    parity_line=$(grep "^$PARITY_KEY" "$version_file" || true)
    parity_report+="   ${version_file#"$BUILD_DIR"/}: ${parity_line:-<missing>}"$'\n'
    if [[ -z "$parity_line" ]]; then
        parity_ok=0
    elif [[ -z "$parity_ref" ]]; then
        parity_ref="$parity_line"
    elif [[ "$parity_line" != "$parity_ref" ]]; then
        parity_ok=0
    fi
done
printf '%s' "$parity_report"
if [[ "$parity_ok" -ne 1 || -z "$parity_ref" ]]; then
    echo "❌ mksquashfs zstd output differs across platforms (or a VERSION.txt is missing the selftest hash)"
    exit 1
fi
echo "✅ All platforms produce identical zstd images"


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

ENTRYPOINTS=("mksquashfs" "unsquashfs" "desktop-file-validate" "opj_decompress")
for entry in "${ENTRYPOINTS[@]}"; do
    ln -sf appimage-tool "$BUILD_DIR/$entry"
done

echo "✅ Generic AppImage tool wrapper created"

# =============================
# Runtime licenses
# =============================
# The type2-runtime binaries statically link libfuse (LGPL-2.1), squashfuse, musl, zstd, zlib and mimalloc. Their
# license files are fetched at pinned tags and verified by SHA256 (assets/runtime-licenses.tsv). No AppImageKit code
# is bundled, so its license is no longer shipped.
echo ""
echo "📄 Fetching the licenses of the AppImage runtime (type2-runtime $APPIMAGE_TYPE2_RELEASE)..."
lic_init "$BUILD_DIR" runtimes "runtimes/ (AppImage type2-runtime $APPIMAGE_TYPE2_RELEASE)"
RUNTIME_PINS="$ROOT/assets/runtime-licenses.tsv"
lic_fetch_pins "$RUNTIME_PINS" "$APPIMAGE_TYPE2_RELEASE"
for component in $(lic_pins_components "$RUNTIME_PINS"); do
    lic_record "runtimes/runtime-*" "$component"
done
echo "✅ Runtime licenses fetched"

lic_finalize_sources "$BUILD_DIR" "$ROOT/assets/SOURCES-header.md"
echo ""
bash "$VERIFY_LICENSES" "$BUILD_DIR"

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

# Check the licenses of exactly what ships: the archive itself, extracted afresh
echo "🔍 Checking the licenses in $ARCHIVE_NAME..."
mkdir "$STAGING_DIR/final"
tar -xzf "$OUT_DIR/$ARCHIVE_NAME" -C "$STAGING_DIR/final"
bash "$VERIFY_LICENSES" "$STAGING_DIR/final"
[[ -s "$STAGING_DIR/final/LICENSES/SOURCES.md" ]] || { echo "❌ $ARCHIVE_NAME has no LICENSES/SOURCES.md"; exit 1; }
rm -rf "$STAGING_DIR/final"
echo "✅ Done!"
echo "Bundle at: $OUT_DIR/$ARCHIVE_NAME"

rm -rf "$BUILD_DIR"