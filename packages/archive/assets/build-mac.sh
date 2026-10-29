#!/usr/bin/env bash
# Builds the macOS archive toolset for the runner's architecture into <stage>, from the sources build.sh downloaded
# and checked. The tools in bin/ link only macOS system libraries; rpm's Homebrew libraries are copied into lib/ and
# loaded through @rpath. Everything targets macOS $MACOS_MIN.
# Usage: WITH_RPM=1|0 build-mac.sh <stage>
set -euo pipefail

ASSETS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$ASSETS/constants.sh"
SOURCES="$ASSETS/../build/sources"
STAGE="$1"
WORK=/tmp/archive-build
PREFIX="$WORK/prefix" # static liblzma
JOBS=$(sysctl -n hw.ncpu)
ARCH=$(uname -m)
rm -rf "$STAGE" "$WORK"
mkdir -p "$STAGE/bin" "$STAGE/LICENSES" "$WORK"
STAGE=$(cd "$STAGE" && pwd)

export MACOSX_DEPLOYMENT_TARGET="$MACOS_MIN" CC="clang -arch $ARCH" CXX="clang++ -arch $ARCH"
export CFLAGS="-O2 -mmacosx-version-min=$MACOS_MIN" CXXFLAGS="-O2 -mmacosx-version-min=$MACOS_MIN"
# Keep Homebrew out of the tools' builds
BREW_PATH="$PATH"
PATH=$(echo "$PATH" | tr ':' '\n' | grep -v -e '^/opt/homebrew' -e '^/usr/local' | paste -s -d : -)
export PKG_CONFIG=false

unpack() { tar -xf "$SOURCES/$(basename "$1")" -C "$WORK"; }
# license <component> <version> <url> <sha256> <source dir> <license files...>
license() {
    mkdir -p "$STAGE/LICENSES/$1"
    (cd "$WORK/$5" && cp "${@:6}" "$STAGE/LICENSES/$1/")
    echo "$1 $2: $3 (sha256 $4)" >>"$STAGE/LICENSES/SOURCES.txt"
}

unpack "$XZ_URL"
(cd "$WORK/xz-$XZ_VERSION" && ./configure --prefix="$PREFIX" --disable-shared --disable-nls --disable-doc \
    --disable-scripts --disable-xzdec --disable-lzmadec --disable-lzmainfo --disable-lzma-links && make -j"$JOBS" install)
cp "$PREFIX/bin/xz" "$STAGE/bin/xz"
license xz "$XZ_VERSION" "$XZ_URL" "$XZ_SHA256" "xz-$XZ_VERSION" COPYING COPYING.0BSD

unpack "$LZIP_URL"
(cd "$WORK/lzip-$LZIP_VERSION" && ./configure CXX="$CXX" CXXFLAGS="$CXXFLAGS" && make -j"$JOBS")
cp "$WORK/lzip-$LZIP_VERSION/lzip" "$STAGE/bin/lzip"
license lzip "$LZIP_VERSION" "$LZIP_URL" "$LZIP_SHA256" "lzip-$LZIP_VERSION" COPYING AUTHORS

unpack "$TAR_URL"
# tar 1.35 detects iconv but does not link it on macOS (https://savannah.gnu.org/bugs/?64441)
(cd "$WORK/tar-$TAR_VERSION" && ./configure --disable-nls --without-posix-acls --without-xattrs LDFLAGS=-liconv &&
    make -j"$JOBS")
cp "$WORK/tar-$TAR_VERSION/src/tar" "$STAGE/bin/tar"
cp "$WORK/tar-$TAR_VERSION/src/tar" "$STAGE/bin/gtar"
license gnu-tar "$TAR_VERSION" "$TAR_URL" "$TAR_SHA256" "tar-$TAR_VERSION" COPYING AUTHORS

unpack "$BINUTILS_URL"
mkdir -p "$WORK/binutils-build"
(cd "$WORK/binutils-build" && "../binutils-$BINUTILS_VERSION/configure" --disable-nls --disable-werror \
    --disable-shared --enable-deterministic-archives --with-system-zlib --without-zstd --disable-plugins \
    --disable-gdb --disable-gdbserver --disable-sim --disable-gold --disable-ld --disable-gprof --disable-gprofng \
    --disable-libctf && make -j"$JOBS" MAKEINFO=true all-binutils)
cp "$WORK/binutils-build/binutils/ar" "$STAGE/bin/ar"
cp "$WORK/binutils-build/binutils/ar" "$STAGE/bin/gar"
license binutils "$BINUTILS_VERSION" "$BINUTILS_URL" "$BINUTILS_SHA256" "binutils-$BINUTILS_VERSION" COPYING COPYING.LIB COPYING3 COPYING3.LIB

unpack "$LIBARCHIVE_URL"
# zlib, iconv and CommonCrypto (mtree md5/sha256) come from macOS; liblzma from the static xz above
(cd "$WORK/libarchive-$LIBARCHIVE_VERSION" && ./configure --disable-shared --disable-bsdcpio --disable-bsdcat \
    --disable-bsdunzip --disable-acl --disable-xattr --without-bz2lib --without-libb2 --without-lz4 --without-zstd \
    --without-lzo2 --without-xml2 --without-expat --with-zlib --with-lzma \
    CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib" && make -j"$JOBS" bsdtar)
cp "$WORK/libarchive-$LIBARCHIVE_VERSION/bsdtar" "$STAGE/bin/bsdtar"
license libarchive "$LIBARCHIVE_VERSION" "$LIBARCHIVE_URL" "$LIBARCHIVE_SHA256" "libarchive-$LIBARCHIVE_VERSION" COPYING

printf '%s\t%s\n' bin/xz xz bin/lzip lzip bin/tar gnu-tar bin/gtar gnu-tar bin/ar binutils bin/gar binutils \
    bin/bsdtar libarchive bin/bsdtar xz >"$STAGE/LICENSES/MANIFEST.tsv"
for f in "$STAGE"/bin/*; do strip "$f" && codesign --force --sign - "$f"; done

if [ "$WITH_RPM" = 1 ]; then
    # The rpm@1.0.0 build: rpm against Homebrew libraries, which are copied into lib/ and loaded through @rpath
    export PATH="$BREW_PATH"
    unset PKG_CONFIG CC CXX CFLAGS CXXFLAGS
    FORMULAE=(lua popt libarchive libmagic zstd xz libgcrypt libgpg-error gettext)
    brew install -q cmake pkgconf scdoc coreutils "${FORMULAE[@]}"
    BREW=$(brew --prefix)
    export PKG_CONFIG_PATH="$BREW/opt/libarchive/lib/pkgconfig:$BREW/lib/pkgconfig"

    unpack "$RPM_URL"
    patch -d "$WORK/rpm-$RPM_VERSION" -p1 <"$ASSETS/rpm/patches/0001-construct-rpmstrPool-with-new.patch"
    cmake -S "$WORK/rpm-$RPM_VERSION" -B "$WORK/rpm-build" "${RPM_CMAKE_ARGS[@]}" -DWITH_LIBELF=OFF -DWITH_LIBDW=OFF \
        -DCMAKE_PREFIX_PATH="$BREW" -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_INSTALL_NAME_DIR=@rpath \
        -DCMAKE_MACOSX_RPATH=ON -DCMAKE_EXE_LINKER_FLAGS=-Wl,-headerpad_max_install_names \
        -DCMAKE_SHARED_LINKER_FLAGS=-Wl,-headerpad_max_install_names
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
    sed -i '' -E 's#^(%__[A-Za-z0-9_]+[[:space:]]+)/(usr/)?(local/)?s?bin/([^[:space:]/]+)[[:space:]]*$#\1\4#' "$STAGE/lib/rpm/macros"
    mkdir -p "$STAGE/lib/rpm/electron-builder"
    cp "$ASSETS/rpm/electron-builder.macros" "$STAGE/lib/rpm/electron-builder/macros"
    cp -L "$BREW/opt/libmagic/share/misc/magic.mgc" "$STAGE/share/misc/magic.mgc"
    for so in librpm librpmbuild librpmio librpmsign; do
        real=$(find "$WORK/rpm-dest/usr/lib" -maxdepth 1 -name "$so.*.dylib" -type f)
        cp "$real" "$STAGE/lib/$(basename "$(otool -D "$real" | tail -n 1)")"
    done
    cp "$WORK/rpm-$RPM_VERSION/COPYING" "$STAGE/LICENSES/rpm/"
    echo "rpm $RPM_VERSION: $RPM_URL (sha256 $RPM_SHA256)" >>"$STAGE/LICENSES/SOURCES.txt"

    machos() { find "$STAGE/libexec" "$STAGE/lib" -type f -exec sh -c 'file -b "$1" | grep -q Mach-O && echo "$1"' _ {} \; ; }
    # Copy every Homebrew library they load into lib/ (recording its formula) and load it through @rpath
    : >"$WORK/formulae"
    for _ in 1 2 3 4; do
        for f in $(machos); do
            for dep in $(otool -L "$f" | tail -n +2 | awk '{print $1}' | grep -e "^$BREW/" -e '^/usr/local/'); do
                base=$(basename "$dep")
                if [ ! -f "$STAGE/lib/$base" ]; then
                    cp -L "$dep" "$STAGE/lib/$base" && chmod 644 "$STAGE/lib/$base"
                    install_name_tool -id "@rpath/$base" "$STAGE/lib/$base"
                    printf '%s\t%s\n' "lib/$base" "$(grealpath "$dep" | sed -n 's#.*/Cellar/\([^/]*\)/.*#\1#p')" >>"$WORK/formulae"
                fi
                install_name_tool -change "$dep" "@rpath/$base" "$f"
            done
        done
    done
    for f in $(machos); do
        for old in $(otool -l "$f" | awk '/cmd LC_RPATH/{getline; getline; print $2}'); do install_name_tool -delete_rpath "$old" "$f"; done
        install_name_tool -add_rpath "@loader_path/$(grealpath --relative-to="$(dirname "$f")" "$STAGE/lib")" "$f"
        strip -x "$f" && codesign --force --sign - "$f"
    done

    # Licenses: rpm's own files, and each copied library's formula (license files of its keg)
    for f in $(machos); do
        rel=${f#"$STAGE"/}
        case "$rel" in libexec/* | lib/rpm/* | lib/librpm*) printf '%s\trpm\n' "$rel" >>"$STAGE/LICENSES/MANIFEST.tsv" ;; esac
    done
    cat "$WORK/formulae" >>"$STAGE/LICENSES/MANIFEST.tsv"
    for formula in $(cut -f2 "$WORK/formulae" | sort -u); do
        mkdir -p "$STAGE/LICENSES/$formula"
        find "$BREW/opt/$formula/" -maxdepth 1 -type f \( -iname 'LICENSE*' -o -iname 'COPYING*' \) -exec cp {} "$STAGE/LICENSES/$formula/" \;
        # Lua ships no license file; its MIT license is at the end of lua.h
        if [ "$formula" = lua ]; then sed -n '/Copyright (C) .* Lua.org/,$p' "$(find "$BREW/opt/lua/include" -name lua.h | head -n 1)" >"$STAGE/LICENSES/lua/LICENSE"; fi
        echo "$formula $(brew list --versions "$formula" | awk '{print $NF}'): Homebrew bottle of $(brew info --json=v2 "$formula" | jq -r '.formulae[0].urls.stable.url')" >>"$STAGE/LICENSES/SOURCES.txt"
    done
fi

# Self-contained: no Homebrew path is loaded, and nothing needs a newer macOS than MACOS_MIN
for f in "$STAGE"/bin/* $(find "$STAGE/libexec" "$STAGE/lib" -type f 2>/dev/null); do
    file -b "$f" | grep -q Mach-O || continue
    if otool -L "$f" | grep -e /opt/homebrew -e /usr/local; then echo "❌ $f loads a Homebrew library"; exit 1; fi
    minos=$(otool -l "$f" | awk '/minos/{print $2; exit}')
    if [ "$(printf '%s\n' "$minos" "$MACOS_MIN" | sort -V | tail -n 1)" != "$MACOS_MIN" ]; then echo "❌ $f needs macOS $minos"; exit 1; fi
done

for t in xz lzip tar ar bsdtar; do "$STAGE/bin/$t" --version | head -n 1; done >"$STAGE/VERSION.txt"
if [ "$WITH_RPM" = 1 ]; then "$STAGE/bin/rpmbuild" --version >>"$STAGE/VERSION.txt"; fi
echo "built on macOS $(sw_vers -productVersion) ($ARCH), minimum macOS $MACOS_MIN" >>"$STAGE/VERSION.txt"
