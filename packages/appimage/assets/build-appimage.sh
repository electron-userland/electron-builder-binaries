#!/bin/env bash
set -euo pipefail

CWD=$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)

SQUASHFS_TOOLS_VERSION_TAG=${SQUASHFS_TOOLS_VERSION_TAG:-"4.6.1"}
DESKTOP_UTILS_DEPS_VERSION_TAG=${DESKTOP_UTILS_DEPS_VERSION_TAG:-"0.28"}
OPENJPEG_VERSION=${OPENJPEG_VERSION:-"2.5.4"}

# Detect OS
case "$(uname -s)" in
    Linux*)
        OS="linux"
    ;;
    Darwin*)
        OS="darwin"
    ;;
    *)
        echo "❌ Unsupported OS: $(uname -s)"
        exit 1
    ;;
esac

echo "🏗️  AppImage Tools Compiler for $OS"
echo ""

BUILD_DIR="/tmp/appimage-build"
rm -rf "$BUILD_DIR"

# =============================================================================
# Env Detection
# =============================================================================
if [ "$OS" = "linux" ]; then
    # Linux: use TARGETPLATFORM from Docker
    get_arch_dir() {
        case "$TARGETPLATFORM" in
            "linux/amd64") echo "x64" ;;
            "linux/386") echo "ia32" ;;
            "linux/arm64") echo "arm64" ;;
            "linux/arm/v7") echo "arm32" ;;
            *) echo "unknown" ;;
        esac
    }
    
    is_x64() { [ "$TARGETPLATFORM" = "linux/amd64" ]; }
    is_ia32() { [ "$TARGETPLATFORM" = "linux/386" ]; }
    is_arm64() { [ "$TARGETPLATFORM" = "linux/arm64" ]; }
    is_arm32() { [ "$TARGETPLATFORM" = "linux/arm/v7" ]; }
    is_x86() { is_x64 || is_ia32; }
    
    ARCH_DIR=$(get_arch_dir)
    if [ "$ARCH_DIR" = "unknown" ]; then
        echo "❌ Unsupported TARGETPLATFORM: $TARGETPLATFORM"
        exit 1
    fi
    
    TARGETARCH="${TARGETARCH:-unknown}"
    
else
    
    # macOS: use uname
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        ARCH_DIR="x64" # map to NodeJS process.arch
        elif [ "$ARCH" = "arm64" ]; then
        ARCH_DIR="arm64"
    else
        echo "❌ Unsupported architecture: $ARCH"
        exit 1
    fi
    
    TARGETARCH="$ARCH"
    
    # Check for Homebrew
    if ! command -v brew &> /dev/null; then
        echo "❌ Homebrew is required but not installed"
        echo "   Install from: https://brew.sh"
        exit 1
    fi
    
    # Verify required brew packages are installed
    echo "🔍 Checking Homebrew dependencies..."
    REQUIRED_DEPS=("lzo" "xz" "lz4" "zstd" "meson" "ninja" "tree")
    MISSING_DEPS=()
    
    for dep in "${REQUIRED_DEPS[@]}"; do
        if ! brew list "$dep" &> /dev/null; then
            MISSING_DEPS+=("$dep")
        else
            echo "   ✅ $dep is installed"
        fi
    done
    
    if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
        echo "❌ Missing required Homebrew packages: ${MISSING_DEPS[*]}"
        brew install ${MISSING_DEPS[*]}
    fi
    echo "   ✅ All required packages installed"
fi
echo "   Building Target: $TARGETARCH"
echo ""
TARGETVARIANT="${TARGETVARIANT:-}"

# =============================================================================
# Setup directories
# =============================================================================
DEST="${DEST:-$CWD/out/build}"

TEMP_DIR=${TEMP_DIR:-"/tmp/appimage-output"}
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

# build tools
OS_OUTPUT="$TEMP_DIR/$OS"
ARCH_OUTPUT_DIR="$OS_OUTPUT/$ARCH_DIR"

# lib for runtimes go at root
LIB_DIR="$TEMP_DIR/lib"
LIB_DEST="$LIB_DIR/$ARCH_DIR"

echo "🏗️  Building for $OS/$ARCH_DIR"
echo ""

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo "   📥 Cloning squashfs-tools..."
git clone https://github.com/plougher/squashfs-tools.git
cd $BUILD_DIR/squashfs-tools
git checkout $SQUASHFS_TOOLS_VERSION_TAG
echo "   ✅ squashfs-tools cloned"

cd "$BUILD_DIR"
git clone https://gitlab.freedesktop.org/xdg/desktop-file-utils.git
cd $BUILD_DIR/desktop-file-utils
git checkout $DESKTOP_UTILS_DEPS_VERSION_TAG
echo "   ✅ desktop-file-utils cloned"

# =============================================================================
# BUILD SQUASHFS-TOOLS
# =============================================================================
echo "📦 Building squashfs-tools..."
cd $BUILD_DIR/squashfs-tools/squashfs-tools

if [ "$OS" = "linux" ]; then
    
    make -j$(nproc) \
    GZIP_SUPPORT=1 \
    XZ_SUPPORT=1 \
    LZO_SUPPORT=1 \
    LZ4_SUPPORT=1 \
    ZSTD_SUPPORT=1
    
    mkdir -p "$ARCH_OUTPUT_DIR"
    cp -aL mksquashfs "$ARCH_OUTPUT_DIR/"
    chmod +x "$ARCH_OUTPUT_DIR/mksquashfs"
    
else
    
    BREW_PREFIX=$(brew --prefix)
    make -j$(sysctl -n hw.ncpu) \
    GZIP_SUPPORT=1 \
    XZ_SUPPORT=1 \
    LZO_SUPPORT=1 \
    LZ4_SUPPORT=1 \
    ZSTD_SUPPORT=1 \
    EXTRA_CFLAGS="-I${BREW_PREFIX}/include" \
    EXTRA_LDFLAGS="-L${BREW_PREFIX}/lib"
    
    mkdir -p "$ARCH_OUTPUT_DIR"
    cp mksquashfs "$ARCH_OUTPUT_DIR/"
    chmod +x "$ARCH_OUTPUT_DIR/mksquashfs"
    
fi

echo "   ✅ Built mksquashfs"

# =============================================================================
# BUILD DESKTOP-FILE-UTILS
# =============================================================================
echo ""
echo "📦 Building desktop-file-utils..."
cd "$BUILD_DIR/desktop-file-utils"

BUILD=$BUILD_DIR/desktop-file-utils/build
meson setup "$BUILD" \
--prefix=/usr \
--buildtype=release
ninja -C "$BUILD"
DESTDIR="$BUILD" ninja -C "$BUILD" install
cp -aL "$BUILD/usr/bin/desktop-file-validate" "$ARCH_OUTPUT_DIR/"
chmod +x "$ARCH_OUTPUT_DIR/desktop-file-validate"
echo "   ✅ Built desktop-file-validate"

# =============================================================================
# BUILD OPENJPEG
# =============================================================================
echo ""
echo "🖼️  Building OpenJPEG..."

TMP_BUILD_DIR="$(mktemp -d)"
INSTALL_DIR="$(mktemp -d)"

cd "$TMP_BUILD_DIR" || exit 1

# Download source using curl
curl -sSL "https://github.com/uclouvain/openjpeg/archive/v${OPENJPEG_VERSION}.tar.gz" -o "v${OPENJPEG_VERSION}.tar.gz"

# Extract
tar xzf "v${OPENJPEG_VERSION}.tar.gz"
cd "openjpeg-${OPENJPEG_VERSION}" || exit 1

# Build
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local > /dev/null
if [ "$OS" = "linux" ]; then
    make -j$(nproc)
else
    make -j$(sysctl -n hw.ncpu)
fi
make install DESTDIR="$INSTALL_DIR"

# Prepare output directory
mkdir -p "$ARCH_OUTPUT_DIR/lib"
cp -a "$INSTALL_DIR/usr/local/lib/libopenjp2."* "$ARCH_OUTPUT_DIR/lib/"
cp -a "$INSTALL_DIR/usr/local/lib/pkgconfig" "$ARCH_OUTPUT_DIR/lib/"
cp -aL "$INSTALL_DIR/usr/local/bin/opj_decompress" "$ARCH_OUTPUT_DIR/"

echo "   ✅ Built OpenJPEG and opj_decompress"

rm -rf "$TMP_BUILD_DIR" "$INSTALL_DIR"

# =============================================================================
# PATCH BINARIES
# =============================================================================
EXECS_TO_PATCH=("mksquashfs" "opj_decompress") # desktop-file-validate copy->patch skipped for now due to bundle size increase

copy_lib_recursive() {
    local lib_path="$1"
    local dest_dir="$2"
    local libname
    libname=$(basename "$lib_path")
    
    # Already handled
    if [ -e "$dest_dir/$libname" ]; then
        return 0
    fi
    
    # Resolve real file
    local real_file
    real_file=$(readlink -f "$lib_path")
    
    # Copy real file
    cp -a "$real_file" "$dest_dir/"
    echo "      ✅ $libname"
    
    # Recreate symlink if this is one
    if [ -L "$lib_path" ]; then
        ln -sf "$(basename "$real_file")" "$dest_dir/$libname"
        
        # Follow symlink chain safely
        local next_target
        next_target=$(readlink "$lib_path")
        
        if [ -n "$next_target" ]; then
            if [[ "$next_target" != /* ]]; then
                next_target="$(dirname "$lib_path")/$next_target"
            fi
            copy_lib_recursive "$next_target" "$dest_dir"
        fi
    fi
}

find "$ARCH_OUTPUT_DIR" -type f -perm -111 | while read -r binary; do
    
    if [[ " ${EXECS_TO_PATCH[*]} " != *"$(basename "$binary")"* ]]; then
        continue
    fi
    
    mkdir -p "$ARCH_OUTPUT_DIR/lib"
    
    if [ "$OS" = "darwin" ]; then
        echo ""
        echo "   🔧 Patching Darwin $binary..."

        install_name_tool -delete_rpath "$ARCH_OUTPUT_DIR/lib" "$binary" 2>/dev/null || true

        # Set a relative RPATH pointing to lib/
        install_name_tool -add_rpath "@loader_path/lib" "$binary"

        otool -L "$binary" | grep -v ":" | grep -v "@" | awk '{print $1}' | while read -r lib; do
            if [[ "$lib" == /usr/local/* ]] || [[ "$lib" == /opt/homebrew/* ]]; then
                libname=$(basename "$lib")
                
                copy_lib_recursive "$lib" "$ARCH_OUTPUT_DIR/lib"
                echo "      ✅ Copied $libname"

                install_name_tool -change "$lib" "@executable_path/lib/$libname" "$binary" 2>/dev/null || \
                install_name_tool -change "$lib" "@loader_path/lib/$libname" "$binary" 2>/dev/null || \
                echo "      ❌ Failed to patch $libname in $binary"
            fi
        done        
    else
        echo ""
        echo "   🔧 Patching Linux $(basename "$binary")..."
        
        # Collect all non-system shared library dependencies
        ldd "$binary" | awk '/=> \// { print $3 }' | while read -r lib; do
            libname=$(basename "$lib")
            
            # Skip system libraries
            case "$libname" in
                libc.so.*|ld-linux*.so.*|libpthread.so.*|librt.so.*|libdl.so.*)
                    continue
                ;;
            esac
            
            echo "      🔄 Copying $libname and its symlink chain..."
            copy_lib_recursive "$lib" "$ARCH_OUTPUT_DIR/lib"
        done
        
        # Make the binary hermetic
        patchelf --remove-rpath "$binary" 2>/dev/null || true
        patchelf --force-rpath --set-rpath '$ORIGIN/../lib' "$binary"        
    fi
done

# =============================================================================
# STRIP BINARIES
# =============================================================================
echo "✂️ Stripping symbols and measuring size savings..."
total_saved=0
# Platform detection
if [[ "$(uname -s)" == "Darwin" ]]; then
    STAT_CMD='stat -f%z'
    STRIP_CMD='strip -x'
else
    STAT_CMD='stat -c%s'
    STRIP_CMD='strip --strip-unneeded'
fi
# Strip and log
find "$ARCH_OUTPUT_DIR" \( -name '*.dylib' -o -name '*.so' -o -name '*.so.*' -o -name '*.bundle' -o -type f -perm -111 \) | while read -r bin; do
    if [[ ! -f "$bin" || -L "$bin" ]]; then
        # echo "  ⏭️  Skipping (symlink or invalid): $bin"
        continue
    fi
    orig_size=$($STAT_CMD "$bin" 2>/dev/null || echo 0)
    
    if $STRIP_CMD "$bin" 2>/dev/null; then
        new_size=$($STAT_CMD "$bin" 2>/dev/null || echo 0)
        if [[ "$new_size" -gt 0 && "$orig_size" -gt "$new_size" ]]; then
            saved=$((orig_size - new_size))
            total_saved=$((total_saved + saved))
        else
            saved=0
        fi
        printf "  ➖ Stripped: %-60s saved: %6d bytes\n" "$(basename "$bin")" "$saved"
    else
        echo "  ⚠️ Could not strip: $bin"
    fi
done
echo "💾 Total space saved: $total_saved bytes (~$((total_saved / 1024)) KB)"

if [ "$OS" = "darwin" ]; then
    # sign every dylib and executable with adhoc identity
    echo "🔏 Code signing binaries and libraries..."
    for f in "$ARCH_OUTPUT_DIR"/lib/*.dylib "$ARCH_OUTPUT_DIR"/*; do
        if [ ! -f "$f" ]; then
            continue
        fi
        echo "   Signing $f"
        /usr/bin/codesign --force --sign - "$f" 2>/dev/null || ( echo "   ❌ Failed to sign $f"; exit 1 )
    done
    # verify signatures (should not print errors)
    /usr/bin/codesign -v --deep --strict "$ARCH_OUTPUT_DIR"/mksquashfs
fi

# =============================================================================
# GRAB BINARY VERSIONS
# =============================================================================
VERSION_FILE="$ARCH_OUTPUT_DIR/VERSION.txt"
echo ""
echo "🔍 Verifying binaries and recording versions..."
: > "$VERSION_FILE"

echo "AppImage Tools Versions for $OS/$ARCH_DIR" >> "$VERSION_FILE"
echo "----------------------------------------" >> "$VERSION_FILE"
echo "openjpeg: $OPENJPEG_VERSION" >> "$VERSION_FILE"

if MKSQ_VER=$(LD_LIBRARY_PATH= "$ARCH_OUTPUT_DIR/mksquashfs" -version | head -n1 2>&1); then
    echo "mksquashfs: $MKSQ_VER" >> "$VERSION_FILE"
    echo "   ✅ mksquashfs verified: $MKSQ_VER"
else
    echo "   ❌ mksquashfs verification failed"
    exit 1
fi

if "$ARCH_OUTPUT_DIR/desktop-file-validate" --help > /dev/null 2>&1; then
    echo "desktop-file-validate: $DESKTOP_UTILS_DEPS_VERSION_TAG" >> "$VERSION_FILE"
    echo "   ✅ desktop-file-validate verified: $DESKTOP_UTILS_DEPS_VERSION_TAG"
else
    echo "   ❌ desktop-file-validate verification failed"
    exit 1
fi

# =============================================================================
# COPY RUNTIME LIBRARIES
# =============================================================================
echo ""
echo "📚 Copying runtime libraries..."

if [ "$OS" = "linux" ]; then
    # Determine system library directory
    if is_ia32; then
        SYS_LIB_DIR="/usr/lib/i386-linux-gnu"
        elif is_x64; then
        SYS_LIB_DIR="/usr/lib/x86_64-linux-gnu"
        elif is_arm64; then
        SYS_LIB_DIR="/usr/lib/aarch64-linux-gnu"
        elif is_arm32; then
        SYS_LIB_DIR="/usr/lib/arm-linux-gnueabihf"
    fi
    
    # Helper function to find and copy library
    copy_lib() {
        local libname=$1
        local outname=${2:-$libname}
        
        # For i386 appindicator, check extracted .deb first
        if is_ia32 && [[ "$libname" == "libappindicator"* || "$libname" == "libindicator"* ]]; then
            for deb_dir in /tmp/appind /tmp/ind; do
                if [ -f "$deb_dir/usr/lib/i386-linux-gnu/$libname" ]; then
                    copy_lib_recursive "$deb_dir/usr/lib/i386-linux-gnu/$libname" "$LIB_DEST"
                    echo "   ✅ $libname"
                    return 0
                fi
            done
        fi
        
        # Search standard library directories
        local search_dirs=(
            "$SYS_LIB_DIR"
            "/usr/lib/i386-linux-gnu"
            "/usr/lib/x86_64-linux-gnu"
            "/usr/lib/aarch64-linux-gnu"
            "/usr/lib/arm-linux-gnueabihf"
        )
        
        for dir in "${search_dirs[@]}"; do
            if [ -f "$dir/$libname" ]; then
                copy_lib_recursive "$dir/$libname" "$LIB_DEST"
                echo "   ✅ $libname"
                return 0
            fi
        done
        
        echo "   ❌ $libname not found"
        return 1
    }
    
    # Copy required librariesq
    mkdir -p "$LIB_DEST"
    
    copy_lib "libXss.so.1" || exit 1
    copy_lib "libXtst.so.6" || exit 1
    copy_lib "libnotify.so.4" || exit 1
    copy_lib "libgconf-2.so.4" || exit 1
    
    if is_ia32; then
        copy_lib "libappindicator.so.1" || exit 1
        copy_lib "libindicator.so.7" || exit 1
    else
        copy_lib "libappindicator3.so.1" "libappindicator.so.1" || exit 1
        copy_lib "libindicator3.so.7" "libindicator.so.7" || exit 1
    fi
fi

echo "   ✅ All libraries copied successfully"

# =============================================================================
# CREATE ARCHIVE
# =============================================================================
echo ""
echo "📦 Creating archive..."

ARCHIVE_NAME="appimage-tools-${OS}-${TARGETARCH}${TARGETVARIANT}.tar.gz"
mkdir -p "$DEST"

items=( "$(basename "$OS_OUTPUT")" )
if [ -d "$LIB_DIR" ]; then
    items+=( "$(basename "$LIB_DIR")" )
fi

(
    cd "$TEMP_DIR"
    tar czf "$DEST/$ARCHIVE_NAME" "${items[@]}"
)

echo ""
echo "🎉 Build complete!"
echo "   Archive: $DEST/$ARCHIVE_NAME"
echo ""
echo "Files created:"
tree $ARCH_OUTPUT_DIR -L 6 2>/dev/null || find $ARCH_OUTPUT_DIR -type f -maxdepth 6

rm -rf "$TEMP_DIR" "$BUILD_DIR"