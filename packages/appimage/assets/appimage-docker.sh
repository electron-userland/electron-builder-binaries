#!/bin/bash
set -e

CWD=$(cd "$(dirname "$BASH_SOURCE")" && pwd)

# Determine architecture directory based on platform
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

ARCH_DIR=$(get_arch_dir)
OUTPUT_DIR="$CWD/output"
DEST="$OUTPUT_DIR/$ARCH_DIR"
echo "Building for $TARGETPLATFORM -> $ARCH_DIR"

# Build squashfs-tools
echo "Building squashfs-tools..."
cd /build/squashfs-tools/squashfs-tools
make -j$(nproc) GZIP_SUPPORT=1 XZ_SUPPORT=1 LZO_SUPPORT=1 LZ4_SUPPORT=1 ZSTD_SUPPORT=1

mkdir -p "$DEST"
cp -aL mksquashfs "$DEST/"
echo "✓ Built mksquashfs"

# Copy desktop-file-validate
cp -aL /usr/bin/desktop-file-validate "$DEST/"
echo "✓ Copied desktop-file-validate"

VERSION_FILE="$DEST/VERSION.txt"

echo "Verifying binaries and recording versions..."
: > "$VERSION_FILE"

# Verify mksquashfs
if MKSQ_VER=$("$DEST/mksquashfs" -version | head -n1 2>&1); then
    echo "mksquashfs: $MKSQ_VER" >> "$VERSION_FILE"
    echo "✓ mksquashfs verified"
else
    echo "❌ mksquashfs verification failed"
    exit 1
fi

# Verify desktop-file-validate. (There's no --version, so we just run it to see if it works and then use dpkg-query to get version)
"$DEST/desktop-file-validate" --help > /dev/null 2>&1
if DFV_VER=$(dpkg-query -W -f='${Version}\n' desktop-file-utils 2>&1); then
    echo "desktop-file-validate: $DFV_VER" >> "$VERSION_FILE"
    echo "✓ desktop-file-validate verified"
else
    echo "❌ desktop-file-validate verification failed"
    exit 1
fi

# Build OpenJPEG (only for x64)
if is_x64; then
    echo "Building OpenJPEG..."
    cd /build
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
    echo "✓ Built OpenJPEG"
fi

# Extract runtime libraries (only for x86 architectures)
if is_x86; then
    echo "Installing runtime libraries..."
    apt-get update -qq
    
    # Install packages and verify they succeeded
    echo "  Installing libxss1..."
    apt-get install -y libxss1 || { echo "  ❌ Failed to install libxss1"; exit 1; }
    
    echo "  Installing libxtst6..."
    apt-get install -y libxtst6 || { echo "  ❌ Failed to install libxtst6"; exit 1; }
    
    echo "  Installing libnotify4..."
    apt-get install -y libnotify4 || { echo "  ❌ Failed to install libnotify4"; exit 1; }
    
    echo "  Installing libgconf-2-4..."
    apt-get install -y libgconf-2-4 || { echo "  ❌ Failed to install libgconf-2-4"; exit 1; }
    
    # libappindicator3-1 only available for x64 in Ubuntu 20.04
    # For i386: we'll download the .deb from Ubuntu 18.04 archives
    if is_x64; then
        echo "  Installing libappindicator3-1..."
        apt-get install -y libappindicator3-1 || { echo "  ❌ Failed to install libappindicator3-1"; exit 1; }
        
        echo "  Installing libindicator3-7..."
        apt-get install -y libindicator3-7 || { echo "  ❌ Failed to install libindicator3-7"; exit 1; }
        
        LIB_DIR="/usr/lib/x86_64-linux-gnu"
        OUT_DIR="$OUTPUT_DIR/lib/x64"
    else
        echo "  Downloading libappindicator1 from Ubuntu 18.04 archive (not available in 20.04 i386)..."
        cd /tmp
        wget -q http://archive.ubuntu.com/ubuntu/pool/universe/liba/libappindicator/libappindicator1_12.10.1+18.04.20180322.1-0ubuntu1_i386.deb
        wget -q http://archive.ubuntu.com/ubuntu/pool/universe/libi/libindicator/libindicator7_16.10.0+18.04.20180321.1-0ubuntu1_i386.deb
        dpkg -x libappindicator1_12.10.1+18.04.20180322.1-0ubuntu1_i386.deb /tmp/appind
        dpkg -x libindicator7_16.10.0+18.04.20180321.1-0ubuntu1_i386.deb /tmp/ind
        LIB_DIR="/usr/lib/i386-linux-gnu"
        OUT_DIR="$OUTPUT_DIR/lib/ia32"
    fi
    
    mkdir -p "$OUT_DIR"
    
    echo "  Copying libraries to $OUT_DIR"
    
    # Helper function to find and copy library
    copy_lib() {
        local libname=$1
        local outname=${2:-$libname}
        
        # For i386 appindicator, check extracted .deb first
        if is_ia32 && [[ "$libname" == "libappindicator"* || "$libname" == "libindicator"* ]]; then
            if [ -f "/tmp/appind/usr/lib/i386-linux-gnu/$libname" ]; then
                cp "/tmp/appind/usr/lib/i386-linux-gnu/$libname" "$OUT_DIR/$outname"
                echo "  ✓ Copied $libname from extracted .deb"
                return 0
            fi
            if [ -f "/tmp/ind/usr/lib/i386-linux-gnu/$libname" ]; then
                cp "/tmp/ind/usr/lib/i386-linux-gnu/$libname" "$OUT_DIR/$outname"
                echo "  ✓ Copied $libname from extracted .deb"
                return 0
            fi
        fi
        
        # Try common locations
        local search_dirs=("$LIB_DIR" "/usr/lib/i386-linux-gnu" "/usr/lib/x86_64-linux-gnu")
        
        for dir in "${search_dirs[@]}"; do
            if [ -f "$dir/$libname" ]; then
                cp "$dir/$libname" "$OUT_DIR/$outname"
                echo "  ✓ Copied $libname from $dir"
                return 0
            fi
        done
        
        echo "  ❌ $libname not found"
        return 1
    }
    
    # Copy all required libraries
    copy_lib "libXss.so.1" || exit 1
    copy_lib "libXtst.so.6" || exit 1
    copy_lib "libnotify.so.4" || exit 1
    copy_lib "libgconf-2.so.4" || exit 1
    
    if is_x64; then
        copy_lib "libappindicator3.so.1" "libappindicator.so.1" || exit 1
        copy_lib "libindicator3.so.7" "libindicator.so.7" || exit 1
    else
        copy_lib "libappindicator.so.1" || exit 1
        copy_lib "libindicator.so.7" || exit 1
    fi
    
    echo "  ✅ All required libraries copied"
fi

echo "Final output directory structure:"
tree "$OUTPUT_DIR" -L 5 2>/dev/null || find "$OUTPUT_DIR" -maxdepth 5 -type f

# Create tarball
echo "Creating tarball..."
cd "$OUTPUT_DIR"
tar czf "/appimage-tools-${TARGETARCH}${TARGETVARIANT}.tar.gz" .
chmod 644 /appimage-tools-*.tar.gz

echo "✓ Build complete for $ARCH_DIR"