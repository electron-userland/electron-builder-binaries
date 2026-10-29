#!/usr/bin/env bash
# Builds the Linux archive toolset into <stage>, inside a manylinux container (see ../build.sh), from the sources
# build.sh downloaded and checked. Every tool in bin/ is linked statically except for the C library.
# Usage: WITH_RPM=1|0 build-linux.sh <stage>
set -euo pipefail

ASSETS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$ASSETS/constants.sh"
SOURCES="$ASSETS/../build/sources"
STAGE="$1"
WORK=/tmp/archive-build
PREFIX="$WORK/prefix" # static zlib and liblzma
MD="$WORK/libmd"      # kept apart: binutils has its own md5.h
JOBS=$(nproc)
rm -rf "$STAGE" "$WORK"
mkdir -p "$STAGE/bin" "$STAGE/LICENSES" "$WORK"
export CFLAGS="-O2 -fPIC" FORCE_UNSAFE_CONFIGURE=1 # tar's configure refuses to run as root otherwise

unpack() { tar -xf "$SOURCES/$(basename "$1")" -C "$WORK"; }
# license <component> <version> <url> <sha256> <source dir> <license files...>
license() {
    mkdir -p "$STAGE/LICENSES/$1"
    (cd "$WORK/$5" && cp "${@:6}" "$STAGE/LICENSES/$1/")
    echo "$1 $2: $3 (sha256 $4)" >>"$STAGE/LICENSES/SOURCES.txt"
}

unpack "$ZLIB_URL"
(cd "$WORK/zlib-$ZLIB_VERSION" && ./configure --static --prefix="$PREFIX" && make -j"$JOBS" install)
license zlib "$ZLIB_VERSION" "$ZLIB_URL" "$ZLIB_SHA256" "zlib-$ZLIB_VERSION" LICENSE

unpack "$LIBMD_URL"
(cd "$WORK/libmd-$LIBMD_VERSION" && ./configure --prefix="$MD" --disable-shared && make -j"$JOBS" install)
license libmd "$LIBMD_VERSION" "$LIBMD_URL" "$LIBMD_SHA256" "libmd-$LIBMD_VERSION" COPYING

unpack "$XZ_URL"
(cd "$WORK/xz-$XZ_VERSION" && ./configure --prefix="$PREFIX" --disable-shared --disable-nls --disable-doc \
    --disable-scripts --disable-xzdec --disable-lzmadec --disable-lzmainfo --disable-lzma-links && make -j"$JOBS" install)
cp "$PREFIX/bin/xz" "$STAGE/bin/xz"
license xz "$XZ_VERSION" "$XZ_URL" "$XZ_SHA256" "xz-$XZ_VERSION" COPYING COPYING.0BSD

unpack "$LZIP_URL"
(cd "$WORK/lzip-$LZIP_VERSION" && ./configure CXXFLAGS=-O2 LDFLAGS="-static-libstdc++ -static-libgcc" && make -j"$JOBS")
cp "$WORK/lzip-$LZIP_VERSION/lzip" "$STAGE/bin/lzip"
license lzip "$LZIP_VERSION" "$LZIP_URL" "$LZIP_SHA256" "lzip-$LZIP_VERSION" COPYING AUTHORS

unpack "$TAR_URL"
# i386 is built against glibc 2.17, which has no 64-bit time_t for 32-bit code
Y2038=""
if [ "$(getconf LONG_BIT)" = 32 ]; then Y2038=--disable-year2038; fi
(cd "$WORK/tar-$TAR_VERSION" && ./configure --disable-nls --without-selinux --without-posix-acls --without-xattrs \
    $Y2038 && make -j"$JOBS")
cp "$WORK/tar-$TAR_VERSION/src/tar" "$STAGE/bin/tar"
cp "$WORK/tar-$TAR_VERSION/src/tar" "$STAGE/bin/gtar"
license gnu-tar "$TAR_VERSION" "$TAR_URL" "$TAR_SHA256" "tar-$TAR_VERSION" COPYING AUTHORS

unpack "$BINUTILS_URL"
mkdir -p "$WORK/binutils-build"
(cd "$WORK/binutils-build" && CFLAGS="$CFLAGS -I$PREFIX/include" LDFLAGS="-L$PREFIX/lib" \
    "../binutils-$BINUTILS_VERSION/configure" --disable-nls --disable-werror --disable-shared \
    --enable-deterministic-archives --with-system-zlib --without-zstd --disable-plugins --disable-gdb \
    --disable-gdbserver --disable-sim --disable-gold --disable-ld --disable-gprof --disable-gprofng --disable-libctf &&
    make -j"$JOBS" MAKEINFO=true all-binutils)
cp "$WORK/binutils-build/binutils/ar" "$STAGE/bin/ar"
cp "$WORK/binutils-build/binutils/ar" "$STAGE/bin/gar"
license binutils "$BINUTILS_VERSION" "$BINUTILS_URL" "$BINUTILS_SHA256" "binutils-$BINUTILS_VERSION" COPYING COPYING.LIB COPYING3 COPYING3.LIB

unpack "$LIBARCHIVE_URL"
(cd "$WORK/libarchive-$LIBARCHIVE_VERSION" && ./configure --disable-shared --disable-bsdcpio --disable-bsdcat \
    --disable-bsdunzip --disable-acl --disable-xattr --without-bz2lib --without-libb2 --without-lz4 --without-zstd \
    --without-lzo2 --without-openssl --without-xml2 --without-expat --with-zlib --with-lzma --with-md \
    CPPFLAGS="-I$PREFIX/include -I$MD/include" LDFLAGS="-L$PREFIX/lib -L$MD/lib" LIBS=-pthread &&
    make -j"$JOBS" bsdtar)
cp "$WORK/libarchive-$LIBARCHIVE_VERSION/bsdtar" "$STAGE/bin/bsdtar"
license libarchive "$LIBARCHIVE_VERSION" "$LIBARCHIVE_URL" "$LIBARCHIVE_SHA256" "libarchive-$LIBARCHIVE_VERSION" COPYING

strip --strip-unneeded "$STAGE"/bin/*
printf '%s\t%s\n' bin/xz xz bin/lzip lzip bin/tar gnu-tar bin/gtar gnu-tar bin/ar binutils bin/ar zlib bin/gar binutils \
    bin/gar zlib bin/bsdtar libarchive bin/bsdtar xz bin/bsdtar zlib bin/bsdtar libmd >"$STAGE/LICENSES/MANIFEST.tsv"

if [ "$WITH_RPM" = 1 ]; then
    # The rpm@1.0.0 build: rpm against the image's libraries, which are copied into lib/ with a relative RPATH
    unset CFLAGS
    dnf -y -q install dnf-plugins-core
    dnf config-manager --set-enabled powertools
    dnf -y -q install cmake make patch bzip2 pkgconf-pkg-config binutils file gettext lua-devel popt-devel \
        file-devel libarchive-devel zlib-devel bzip2-devel xz-devel libzstd-devel elfutils-libelf-devel \
        elfutils-devel libgcrypt-devel
    # rpm wants scdoc for man pages (not shipped), and libgcrypt.pc, which EL8's libgcrypt 1.8 lacks
    mkdir -p "$WORK/fakebin" "$WORK/pkgconfig"
    printf '#!/bin/sh\ncat >/dev/null\n' >"$WORK/fakebin/scdoc" && chmod 755 "$WORK/fakebin/scdoc"
    printf 'Name: libgcrypt\nDescription: libgcrypt\nVersion: %s\nCflags: %s\nLibs: %s\n' "$(libgcrypt-config --version)" \
        "$(libgcrypt-config --cflags)" "$(libgcrypt-config --libs)" >"$WORK/pkgconfig/libgcrypt.pc"
    export PATH="$WORK/fakebin:$PATH" PKG_CONFIG_PATH="$WORK/pkgconfig"

    unpack "$RPM_URL"
    patch -d "$WORK/rpm-$RPM_VERSION" -p1 <"$ASSETS/rpm/patches/0001-construct-rpmstrPool-with-new.patch"
    cmake -S "$WORK/rpm-$RPM_VERSION" -B "$WORK/rpm-build" "${RPM_CMAKE_ARGS[@]}"
    cmake --build "$WORK/rpm-build" -j"$JOBS"
    DESTDIR="$WORK/rpm-dest" cmake --install "$WORK/rpm-build" >/dev/null

    # bin/rpm{,build} are wrappers: they run libexec/ with lib/rpm and share/misc/magic.mgc relative to bin/
    mkdir -p "$STAGE/libexec" "$STAGE/lib" "$STAGE/share/misc" "$STAGE/LICENSES/rpm"
    for t in rpm rpmbuild; do
        cp "$WORK/rpm-dest/usr/bin/$t" "$STAGE/libexec/$t"
        cp "$ASSETS/rpm/wrapper.sh" "$STAGE/bin/$t"
    done
    cp -R "$WORK/rpm-dest/usr/lib/rpm" "$STAGE/lib/rpm"
    for f in "${RPM_CONFIGDIR_DROP[@]}"; do rm -rf "${STAGE:?}/lib/rpm/$f"; done
    # helper tools resolve through PATH (%__tar is tar, ...), not the build host's absolute paths
    sed -i -E 's#^(%__[A-Za-z0-9_]+[[:space:]]+)/(usr/)?(local/)?s?bin/([^[:space:]/]+)[[:space:]]*$#\1\4#' "$STAGE/lib/rpm/macros"
    mkdir -p "$STAGE/lib/rpm/electron-builder"
    cp "$ASSETS/rpm/electron-builder.macros" "$STAGE/lib/rpm/electron-builder/macros"
    cp -L /usr/share/misc/magic.mgc "$STAGE/share/misc/magic.mgc"
    for so in librpm librpmbuild librpmio librpmsign; do
        real=$(find "$WORK/rpm-dest/usr/lib" -maxdepth 1 -name "$so.so.*" -type f)
        cp "$real" "$STAGE/lib/$(objdump -p "$real" | awk '/SONAME/{print $2}')"
    done
    cp "$WORK/rpm-$RPM_VERSION/COPYING" "$STAGE/LICENSES/rpm/"
    echo "rpm $RPM_VERSION: $RPM_URL (sha256 $RPM_SHA256)" >>"$STAGE/LICENSES/SOURCES.txt"

    elfs=$(find "$STAGE/libexec" "$STAGE/lib" -type f -exec sh -c 'head -c4 "$1" | grep -q ELF && echo "$1"' _ {} \;)
    # Every library they need that glibc and the GCC runtime do not provide
    for _ in 1 2 3; do
        for f in $elfs "$STAGE"/lib/*.so*; do
            LD_LIBRARY_PATH="$STAGE/lib" ldd "$f" | awk '/=> \//{print $1, $3}' | while read -r name path; do
                [[ "$name" =~ ^(ld-linux|libc\.|libm\.|libdl\.|librt\.|libpthread\.|libresolv\.|libutil\.|libstdc\+\+\.|libgcc_s\.) ]] && continue
                [ -e "$STAGE/lib/$name" ] || cp -L "$path" "$STAGE/lib/$name"
            done
        done
    done
    for f in $elfs "$STAGE"/lib/*.so*; do
        rel=$(realpath --relative-to="$(dirname "$f")" "$STAGE/lib")
        # DT_RPATH, not RUNPATH: wins over the LD_LIBRARY_PATH fpm's portable Ruby exports
        patchelf --force-rpath --set-rpath "\$ORIGIN/$rel" "$f"
        strip --strip-unneeded "$f"
    done

    # Licenses: rpm's own files, and each copied library's package (its %license files)
    for f in $elfs "$STAGE"/lib/*.so*; do
        rel=${f#"$STAGE"/}
        case "$rel" in
            libexec/* | lib/rpm/* | lib/librpm*) printf '%s\trpm\n' "$rel" >>"$STAGE/LICENSES/MANIFEST.tsv"; continue ;;
        esac
        pkg=$(rpm -qf --qf '%{NAME}' "/usr/lib64/$(basename "$f")")
        printf '%s\t%s\n' "$rel" "$pkg" >>"$STAGE/LICENSES/MANIFEST.tsv"
        [ -d "$STAGE/LICENSES/$pkg" ] && continue
        mkdir -p "$STAGE/LICENSES/$pkg"
        rpm -qL "$pkg" | xargs -r cp -t "$STAGE/LICENSES/$pkg/"
        # lua-libs ships no license file; Lua's MIT license is at the end of lua.h
        if [ "$pkg" = lua-libs ]; then sed -n '/Copyright (C) .* Lua.org/,$p' /usr/include/lua.h >"$STAGE/LICENSES/$pkg/LICENSE"; fi
        echo "$pkg $(rpm -q --qf '%{VERSION}-%{RELEASE}' "$pkg"): AlmaLinux 8 source package $(rpm -q --qf '%{SOURCERPM}' "$pkg")" >>"$STAGE/LICENSES/SOURCES.txt"
    done
fi

for t in xz lzip tar ar bsdtar; do "$STAGE/bin/$t" --version | head -n 1; done >"$STAGE/VERSION.txt"
if [ "$WITH_RPM" = 1 ]; then "$STAGE/bin/rpmbuild" --version >>"$STAGE/VERSION.txt"; fi
echo "built on $(. /etc/os-release && echo "$PRETTY_NAME"), $(ldd --version | head -n 1)" >>"$STAGE/VERSION.txt"
