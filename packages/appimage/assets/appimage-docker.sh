#!/bin/bash
set -e

CWD=$(cd "$(dirname "$BASH_SOURCE")" && pwd)

# Architecture detection helpers
get_arch_dir() {
    case "$TARGETPLATFORM" in
        "linux/amd64") echo "x64" ;;
        "linux/386") echo "ia32" ;;
        "linux/arm64") echo "arm64" ;;
        "linux/arm/v7") echo "arm32" ;;
        *) echo "linux-unknown" ;;
    esac
}

is_x64() { [ "$TARGETPLATFORM" = "linux/amd64" ]; }
is_ia32() { [ "$TARGETPLATFORM" = "linux/386" ]; }
is_arm64() { [ "$TARGETPLATFORM" = "linux/arm64" ]; }
is_arm32() { [ "$TARGETPLATFORM" = "linux/arm/v7" ]; }
is_x86() { is_x64 || is_ia32; }

# Validate platform
ARCH_DIR=$(get_arch_dir)
if [ "$ARCH_DIR" = "linux-unknown" ]; then
    echo "❌ Unsupported TARGETPLATFORM: $TARGETPLATFORM"
    exit 1
fi

# Setup directories
OUTPUT_DIR="$CWD/linux"
DEST="$OUTPUT_DIR/$ARCH_DIR"
LIB_DIR="$CWD/lib"
LIB_DEST="$LIB_DIR/$ARCH_DIR"

echo "🏗️  Building for $TARGETPLATFORM → $ARCH_DIR"

# =============================================================================
# Build squashfs-tools
# =============================================================================
echo "📦 Building squashfs-tools..."
cd /build/squashfs-tools/squashfs-tools
make -j$(nproc) GZIP_SUPPORT=1 XZ_SUPPORT=1 LZO_SUPPORT=1 LZ4_SUPPORT=1 ZSTD_SUPPORT=1

mkdir -p "$DEST"
cp -aL mksquashfs "$DEST/"
echo "   ✅ Built mksquashfs"

# Copy desktop-file-validate
cp -aL /usr/bin/desktop-file-validate "$DEST/"
echo "   ✅ Copied desktop-file-validate"

# =============================================================================
# Verify binaries and record versions
# =============================================================================
VERSION_FILE="$DEST/VERSION.txt"
echo "🔍 Verifying binaries and recording versions..."
: > "$VERSION_FILE"

# Verify mksquashfs
if MKSQ_VER=$("$DEST/mksquashfs" -version | head -n1 2>&1); then
    echo "mksquashfs: $MKSQ_VER" >> "$VERSION_FILE"
    echo "   ✅ mksquashfs verified"
else
    echo "   ❌ mksquashfs verification failed"
    exit 1
fi

# Verify desktop-file-validate
if "$DEST/desktop-file-validate" --help > /dev/null 2>&1 && \
   DFV_VER=$(dpkg-query -W -f='${Version}\n' desktop-file-utils 2>&1); then
    echo "desktop-file-validate: $DFV_VER" >> "$VERSION_FILE"
    echo "   ✅ desktop-file-validate verified"
else
    echo "   ❌ desktop-file-validate verification failed"
    exit 1
fi

# =============================================================================
# Build OpenJPEG (x64 and arm64 only)
# =============================================================================
if is_x64 || is_arm64; then
    echo "🖼️  Building OpenJPEG..."
    cd /tmp
    wget -q https://github.com/uclouvain/openjpeg/archive/v2.3.0.tar.gz
    tar xzf v2.3.0.tar.gz
    cd openjpeg-2.3.0
    mkdir build && cd build
    cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local > /dev/null
    make -j$(nproc) > /dev/null
    make install DESTDIR=/tmp/openjpeg-install > /dev/null
    
    mkdir -p "$DEST/lib"
    cp -a /tmp/openjpeg-install/usr/local/lib/libopenjp2.* "$DEST/lib/"
    cp -a /tmp/openjpeg-install/usr/local/lib/openjpeg-2.3 "$DEST/lib/"
    cp -a /tmp/openjpeg-install/usr/local/lib/pkgconfig "$DEST/lib/"
    cp -aL /tmp/openjpeg-install/usr/local/bin/opj_decompress "$DEST/"
    
    # Create symlinks
    cd "$DEST/lib"
    ln -sf libopenjp2.so.2.3.0 libopenjp2.so.7
    ln -sf libopenjp2.so.7 libopenjp2.so
    echo "   ✅ Built OpenJPEG"
fi

# =============================================================================
# Install and copy runtime libraries
# =============================================================================
echo "📚 Installing runtime libraries..."
apt-get update -qq

# Common dependencies for all architectures
declare -a common_deps=("libxss1" "libxtst6" "libnotify4" "libgconf-2-4")
for dep in "${common_deps[@]}"; do
    echo "   📥 Installing $dep..."
    if ! apt-get install -y "$dep" > /dev/null 2>&1; then
        echo "   ❌ Failed to install $dep"
        exit 1
    fi
done

# Architecture-specific setup
if is_ia32; then
    echo "   📥 Downloading libappindicator1 from Ubuntu 18.04 archive..."
    cd /tmp
    wget -q http://archive.ubuntu.com/ubuntu/pool/universe/liba/libappindicator/libappindicator1_12.10.1+18.04.20180322.1-0ubuntu1_i386.deb
    wget -q http://archive.ubuntu.com/ubuntu/pool/universe/libi/libindicator/libindicator7_16.10.0+18.04.20180321.1-0ubuntu1_i386.deb
    dpkg -x libappindicator1_12.10.1+18.04.20180322.1-0ubuntu1_i386.deb /tmp/appind
    dpkg -x libindicator7_16.10.0+18.04.20180321.1-0ubuntu1_i386.deb /tmp/ind
    SYS_LIB_DIR="/usr/lib/i386-linux-gnu"
else
    echo "   📥 Installing libappindicator3-1 & libindicator3-7..."
    apt-get install -y libappindicator3-1 libindicator3-7 > /dev/null 2>&1 || {
        echo "   ❌ Failed to install libappindicator/libindicator"
        exit 1
    }
    if is_x64; then
        SYS_LIB_DIR="/usr/lib/x86_64-linux-gnu"
    elif is_arm64; then
        SYS_LIB_DIR="/usr/lib/aarch64-linux-gnu"
    elif is_arm32; then
        SYS_LIB_DIR="/usr/lib/arm-linux-gnueabihf"
    fi
fi

mkdir -p "$LIB_DEST"
echo "   📋 Copying libraries to $LIB_DEST..."

# Helper function to find and copy library
copy_lib() {
    local libname=$1
    local outname=${2:-$libname}
    
    # For i386 appindicator, check extracted .deb first
    if is_ia32 && [[ "$libname" == "libappindicator"* || "$libname" == "libindicator"* ]]; then
        for deb_dir in /tmp/appind /tmp/ind; do
            if [ -f "$deb_dir/usr/lib/i386-linux-gnu/$libname" ]; then
                cp "$deb_dir/usr/lib/i386-linux-gnu/$libname" "$LIB_DEST/$outname"
                echo "      ✅ $libname"
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
            cp "$dir/$libname" "$LIB_DEST/$outname"
            echo "      ✅ $libname"
            return 0
        fi
    done
    
    echo "      ❌ $libname not found"
    return 1
}

# Copy required libraries
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

echo "   ✅ All libraries copied successfully"

# =============================================================================
# Display final structure
# =============================================================================
echo ""
echo "📂 Final output structure:"
tree "$CWD" -L 5 2>/dev/null || find "$CWD" -maxdepth 5 -type f

# =============================================================================
# Create tarball
# =============================================================================
echo ""
echo "📦 Creating tarball..."
cd "$CWD"
tar czf "/appimage-tools-${TARGETARCH}${TARGETVARIANT}.tar.gz" \
    "$(basename "$LIB_DIR")" \
    "$(basename "$OUTPUT_DIR")"
chmod 644 /appimage-tools-*.tar.gz

echo ""
echo "🎉 Build complete for $ARCH_DIR!"