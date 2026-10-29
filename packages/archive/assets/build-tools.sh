#!/usr/bin/env bash
# Builds the archive tools from the verified sources (fetch-sources.sh) into <stage>/bin, with their licenses:
#   bin/xz              XZ Utils, liblzma static
#   bin/lzip            lzip (Linux: libstdc++/libgcc static)
#   bin/tar, bin/gtar   GNU tar (fpm's tar_cmd probes tar, gtar, gnutar; electron-builder calls gtar)
#   bin/ar, bin/gar     GNU ar from binutils, deterministic (-D) by default (fpm's ar_cmd probes ar, then gar)
#   bin/bsdtar          libarchive's bsdtar, libarchive and liblzma static (+ zlib and libmd on Linux)
# Every binary depends on the C library (and on macOS other /usr/lib system libraries) only.
# The aliases are copies, not symlinks, so that every archive format and extractor keeps them.
#   LICENSES/<component>/   license files, copied from the component's verified source tarball
#   LICENSES/MANIFEST.tsv   "<binary><TAB><component>" (scripts/verify-licenses.sh)
#   LICENSES/SOURCES.txt    where the corresponding source of each component is (version, URL, sha256)
#
# Linux: runs inside the build image (build-linux.sh). macOS: runs on the runner (build-mac.sh) and targets the
# runner's architecture and MACOS_MIN, with Homebrew kept out of the build.
#
# Usage: build-tools.sh <sources-dir> <stage-dir>
# Env:   WORK_DIR  scratch directory (default /tmp/archive-tools)
set -euo pipefail

ASSETS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=SCRIPTDIR/constants.sh
source "$ASSETS/constants.sh"
# shellcheck source=SCRIPTDIR/licenses.sh
source "$ASSETS/licenses.sh"

SOURCES=$(cd "${1:?usage: build-tools.sh <sources-dir> <stage-dir>}" && pwd)
STAGE="${2:?usage: build-tools.sh <sources-dir> <stage-dir>}"
WORK="${WORK_DIR:-/tmp/archive-tools}"
OS=$(uname -s)
ARCH=$(uname -m)

rm -rf "$WORK"
mkdir -p "$WORK" "$STAGE/bin" "$STAGE/LICENSES"
STAGE=$(cd "$STAGE" && pwd)
PREFIX="$WORK/prefix"       # static liblzma (xz, bsdtar) and zlib (ar, bsdtar)
MD_PREFIX="$WORK/libmd"     # libmd's md5.h/sha2.h stay out of the binutils build, which has its own md5.h
mkdir -p "$PREFIX/include" "$PREFIX/lib" "$MD_PREFIX"

if [ "$OS" = "Darwin" ]; then
    JOBS=$(sysctl -n hw.ncpu)
    export MACOSX_DEPLOYMENT_TARGET="$MACOS_MIN"
    export CC="clang -arch $ARCH"
    export CXX="clang++ -arch $ARCH"
    export CFLAGS="-O2 -mmacosx-version-min=$MACOS_MIN"
    export CXXFLAGS="$CFLAGS"
    export LDFLAGS="-mmacosx-version-min=$MACOS_MIN"
    # Homebrew's tools, headers and libraries must not leak into the build
    PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v -e '^/opt/homebrew' -e '^/usr/local' | paste -s -d : -)
    export PATH
    unset CPATH LIBRARY_PATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH PKG_CONFIG_PATH DYLD_LIBRARY_PATH
    export PKG_CONFIG=false
else
    JOBS=$(nproc)
    export CC="${CC:-gcc}"
    export CXX="${CXX:-g++}"
    export CFLAGS="-O2 -fPIC"
    export CXXFLAGS="$CFLAGS"
    export LDFLAGS=""
    # only the static libraries built here are visible to pkg-config
    export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
    export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
    # GNU tar's configure refuses to run as root (the build container)
    export FORCE_UNSAFE_CONFIGURE=1
fi

# run_logged <log> <command...>: quiet unless it fails, then the log's tail
run_logged() {
    local log="$1"
    shift
    "$@" >"$log" 2>&1 || {
        echo "❌ $* failed; last lines of $log:" >&2
        tail -80 "$log" >&2
        return 1
    }
}

# install_bin <file> <name...>: strips the binary and installs it under every name
install_bin() {
    local src="$1" name first=""
    shift
    for name in "$@"; do
        cp "$src" "$STAGE/bin/$name"
        chmod 755 "$STAGE/bin/$name"
        if [ "$OS" = "Darwin" ]; then
            strip "$STAGE/bin/$name"
            codesign --force --sign - "$STAGE/bin/$name"
        else
            strip --strip-unneeded "$STAGE/bin/$name"
        fi
        [ -n "$first" ] || first="$name"
    done
    check_deps "$STAGE/bin/$first"
}

# check_deps <binary>: the C library / macOS system libraries only, and (macOS) minos <= MACOS_MIN
check_deps() {
    local f="$1" deps minos
    if [ "$OS" = "Darwin" ]; then
        deps=$(otool -L "$f" | tail -n +2 | awk '{print $1}')
        echo "$deps" | sed "s|^|    $(basename "$f"): |"
        if echo "$deps" | grep -v -e '^/usr/lib/' -e '^/System/' >/dev/null; then
            die "$(basename "$f") links a library outside /usr/lib and /System"
        fi
        minos=$(otool -l "$f" | awk '/LC_BUILD_VERSION/{b=1} b&&/minos/{print $2; b=0}')
        if [ "$(printf '%s\n%s\n' "$minos" "$MACOS_MIN" | sort -V | tail -1)" != "$MACOS_MIN" ]; then
            die "$(basename "$f") requires macOS $minos > $MACOS_MIN"
        fi
        echo "    $(basename "$f"): minos $minos"
    else
        deps=$(env -u LD_LIBRARY_PATH ldd "$f" 2>&1 | awk '{print $1}')
        echo "$deps" | sed "s|^|    $(basename "$f"): |"
        if echo "$deps" | grep -vE '^(linux-vdso\.so|linux-gate\.so|/lib.*/ld-linux|ld-linux|libc\.so|libm\.so|libdl\.so|libpthread\.so|librt\.so)' >/dev/null; then
            die "$(basename "$f") links more than the C library"
        fi
    fi
}

echo "🔨 Archive tools for $OS $ARCH ($($CC --version 2>/dev/null | sed -n 1p))"

# --- XZ Utils --------------------------------------------------------------------------------------------------
SRC=$(extract_source XZ "$SOURCES" "$WORK")
echo "🔨 xz $XZ_VERSION"
(
    cd "$SRC"
    run_logged "$WORK/xz-configure.log" ./configure --prefix="$PREFIX" --disable-shared --enable-static \
        --disable-nls --disable-doc --disable-scripts --disable-xzdec --disable-lzmadec --disable-lzmainfo \
        --disable-lzma-links --disable-dependency-tracking
    run_logged "$WORK/xz-make.log" make -j"$JOBS"
    run_logged "$WORK/xz-install.log" make install
)
install_bin "$PREFIX/bin/xz" xz
echo "eb-archive" | "$STAGE/bin/xz" -z -T0 | "$STAGE/bin/xz" -dc | grep -qx 'eb-archive' || die "xz round trip failed"
# COPYING says which license covers which part: xz and liblzma are 0BSD (COPYING.0BSD); the GPL/LGPL parts
# (scripts, xzdiff/xzgrep, the getopt_long replacement) are not built.
add_component XZ xz-utils "$SRC" "bin/xz is built from this release with liblzma linked statically."
add_binaries xz-utils bin/xz

# --- lzip ------------------------------------------------------------------------------------------------------
SRC=$(extract_source LZIP "$SOURCES" "$WORK")
echo "🔨 lzip $LZIP_VERSION"
LZIP_LDFLAGS="$LDFLAGS"
if [ "$OS" != "Darwin" ]; then LZIP_LDFLAGS="$LDFLAGS -static-libstdc++ -static-libgcc"; fi
(
    cd "$SRC"
    # lzip's own configure takes the variables as arguments
    run_logged "$WORK/lzip-configure.log" ./configure --prefix="$PREFIX" CXX="$CXX" CXXFLAGS="$CXXFLAGS" \
        LDFLAGS="$LZIP_LDFLAGS"
    run_logged "$WORK/lzip-make.log" make -j"$JOBS"
)
install_bin "$SRC/lzip" lzip
note=""
if [ "$OS" != "Darwin" ]; then note=" The GCC C++ runtime is linked statically (GCC Runtime Library Exception)."; fi
add_component LZIP lzip "$SRC" "bin/lzip is built from this release.$note"
add_binaries lzip bin/lzip

# --- zlib and libmd (Linux) --------------------------------------------------------------------------------------
if [ "$OS" != "Darwin" ]; then
    SRC=$(extract_source ZLIB "$SOURCES" "$WORK")
    echo "🔨 zlib $ZLIB_VERSION (static)"
    (
        cd "$SRC"
        run_logged "$WORK/zlib-configure.log" ./configure --static --prefix="$PREFIX"
        run_logged "$WORK/zlib-make.log" make -j"$JOBS"
        run_logged "$WORK/zlib-install.log" make install
    )
    add_component ZLIB zlib "$SRC" "Linked statically into bin/ar, bin/gar and bin/bsdtar."

    SRC=$(extract_source LIBMD "$SOURCES" "$WORK")
    echo "🔨 libmd $LIBMD_VERSION (static)"
    (
        cd "$SRC"
        run_logged "$WORK/libmd-configure.log" ./configure --prefix="$MD_PREFIX" --disable-shared --enable-static \
            --disable-dependency-tracking
        run_logged "$WORK/libmd-make.log" make -j"$JOBS"
        run_logged "$WORK/libmd-install.log" make install
    )
    add_component LIBMD libmd "$SRC" "Linked statically into bin/bsdtar (MD5/SHA-256 digests of mtree archives)."
fi

# --- GNU tar ---------------------------------------------------------------------------------------------------
SRC=$(extract_source TAR "$SOURCES" "$WORK")
echo "🔨 GNU tar $TAR_VERSION"
TAR_LDFLAGS="$LDFLAGS"
TAR_ARGS=()
# tar 1.35 detects iconv but does not link it on macOS (https://savannah.gnu.org/bugs/?64441)
if [ "$OS" = "Darwin" ]; then TAR_LDFLAGS="$LDFLAGS -liconv"; fi
# i386 is built against glibc 2.17, which has no 64-bit time_t for 32-bit code (that needs glibc >= 2.34)
if [ "$OS" != "Darwin" ] && [ "$(getconf LONG_BIT)" = "32" ]; then TAR_ARGS+=(--disable-year2038); fi
(
    cd "$SRC"
    run_logged "$WORK/tar-configure.log" ./configure --prefix="$PREFIX" --disable-nls --disable-dependency-tracking \
        --without-selinux --without-posix-acls --without-xattrs ${TAR_ARGS[@]+"${TAR_ARGS[@]}"} LDFLAGS="$TAR_LDFLAGS"
    run_logged "$WORK/tar-make.log" make -j"$JOBS"
)
install_bin "$SRC/src/tar" tar gtar
"$STAGE/bin/tar" --version | sed -n 1p | grep 'GNU tar' >/dev/null || die "bin/tar is not GNU tar"
add_component TAR gnu-tar "$SRC" "bin/tar and bin/gtar (the same binary) are built from this release."
add_binaries gnu-tar bin/tar bin/gtar

# --- GNU ar (binutils) ------------------------------------------------------------------------------------------
SRC=$(extract_source BINUTILS "$SOURCES" "$WORK")
echo "🔨 GNU binutils $BINUTILS_VERSION (ar)"
mkdir -p "$WORK/binutils-build"
(
    cd "$WORK/binutils-build"
    # Linux: the static zlib above (the top-level configure hands CFLAGS/LDFLAGS to every subdirectory)
    if [ "$OS" != "Darwin" ]; then
        export CFLAGS="$CFLAGS -I$PREFIX/include" LDFLAGS="$LDFLAGS -L$PREFIX/lib"
    fi
    run_logged "$WORK/binutils-configure.log" "$SRC/configure" --prefix="$PREFIX" \
        --disable-nls --disable-werror --disable-shared --enable-static --enable-deterministic-archives \
        --with-system-zlib --without-zstd --without-debuginfod --disable-plugins \
        --disable-gdb --disable-gdbserver --disable-sim --disable-gold --disable-ld --disable-gprof \
        --disable-gprofng --disable-libctf --disable-readline --disable-libdecnumber \
        MAKEINFO=true
    run_logged "$WORK/binutils-make.log" make -j"$JOBS" MAKEINFO=true all-binutils
)
install_bin "$WORK/binutils-build/binutils/ar" ar gar
"$STAGE/bin/ar" --version | sed -n 1p | grep 'GNU ar' >/dev/null || die "bin/ar is not GNU ar"
# fpm's ar_cmd probe: `ar -qc` (then `-qcD`) must write uid/gid 0 and mtime 0
(
    cd "$WORK"
    : >empty
    rm -f probe.a
    "$STAGE/bin/ar" -qc probe.a empty
    env TZ=UTC LANG=C LC_TIME=C "$STAGE/bin/ar" -tv probe.a | grep '0/0.*1970' >/dev/null
) || die "GNU ar does not create deterministic archives by default"
echo "  ✓ ar -qc is deterministic"
# ar, libbfd and libsframe are GPL-3.0-or-later (COPYING3); libiberty is LGPL (COPYING.LIB, COPYING3.LIB)
add_component BINUTILS binutils "$SRC" "bin/ar and bin/gar (the same binary) are binutils' ar, built from this release with libbfd, libsframe and libiberty linked statically."
add_binaries binutils bin/ar bin/gar
if [ "$OS" != "Darwin" ]; then add_binaries zlib bin/ar bin/gar; fi

# --- libarchive (bsdtar) ----------------------------------------------------------------------------------------
SRC=$(extract_source LIBARCHIVE "$SOURCES" "$WORK")
echo "🔨 libarchive $LIBARCHIVE_VERSION (bsdtar)"
LA_ARGS=(--prefix="$PREFIX" --disable-shared --enable-static --enable-bsdtar=static --disable-bsdcpio
    --disable-bsdcat --disable-bsdunzip --disable-acl --disable-xattr --disable-dependency-tracking
    --without-bz2lib --without-libb2 --without-lz4 --without-zstd --without-lzo2 --without-cng --without-nettle
    --without-mbedtls --without-openssl --without-xml2 --without-expat --with-lzma)
if [ "$OS" = "Darwin" ]; then
    # zlib, iconv and CommonCrypto (md5/sha256) from macOS itself
    LA_ARGS+=(--with-zlib --without-md CPPFLAGS="-I$PREFIX/include" LDFLAGS="$LDFLAGS -L$PREFIX/lib")
else
    LA_ARGS+=(--with-zlib --with-md CPPFLAGS="-I$PREFIX/include -I$MD_PREFIX/include"
        LDFLAGS="$LDFLAGS -L$PREFIX/lib -L$MD_PREFIX/lib" LIBS="-pthread")
fi
(
    cd "$SRC"
    run_logged "$WORK/libarchive-configure.log" ./configure "${LA_ARGS[@]}"
    run_logged "$WORK/libarchive-make.log" make -j"$JOBS" bsdtar
)
grep -E '^#define (HAVE_LIBLZMA|HAVE_LIBZ|ARCHIVE_CRYPTO_MD5_[A-Z]+|ARCHIVE_CRYPTO_SHA256_[A-Z]+) 1' "$SRC/config.h" |
    sed 's/^/    /'
for need in HAVE_LIBLZMA HAVE_LIBZ ARCHIVE_CRYPTO_MD5_ ARCHIVE_CRYPTO_SHA256_; do
    grep -E "^#define ${need}[A-Z]* 1" "$SRC/config.h" >/dev/null || die "libarchive was configured without $need"
done
install_bin "$SRC/bsdtar" bsdtar
# what fpm's pacman target runs for .MTREE: gzip plus md5 and sha256 digests
(
    mkdir -p "$WORK/mtree" && cd "$WORK/mtree"
    echo hello >file
    LANG=C "$STAGE/bin/bsdtar" -czf .MTREE --format=mtree \
        --options='!all,use-set,type,uid,gid,mode,time,size,md5,sha256,link' file
    gzip -dc .MTREE | grep 'sha256digest=' | grep 'md5digest=' >/dev/null
) || die "bsdtar cannot write a gzip-compressed mtree with md5/sha256 digests"
echo "  ✓ bsdtar writes gzip mtree with md5/sha256 digests"
add_component LIBARCHIVE libarchive "$SRC" "bin/bsdtar is built from this release with libarchive linked statically."
add_binaries libarchive bin/bsdtar
add_binaries xz-utils bin/bsdtar
if [ "$OS" != "Darwin" ]; then add_binaries zlib bin/bsdtar; add_binaries libmd bin/bsdtar; fi

{
    echo "xz: $("$STAGE/bin/xz" --version | sed -n 1p)"
    echo "lzip: $("$STAGE/bin/lzip" --version | sed -n 1p)"
    echo "tar: $("$STAGE/bin/tar" --version | sed -n 1p)"
    echo "ar: $("$STAGE/bin/ar" --version | sed -n 1p)"
    echo "bsdtar: $("$STAGE/bin/bsdtar" --version | sed -n 1p)"
} >"$WORK/versions.txt"
cat "$WORK/versions.txt"
echo "✅ Archive tools staged in $STAGE/bin"
