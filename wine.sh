#!/usr/bin/env bash
set -e

# custom homebrew prefix and DYLD_FALLBACK_LIBRARY_PATH doesn't work due to unknown reasons on Travis
# homebrew bottle and DYLD_FALLBACK_LIBRARY_PATH doesn't work due to not found library on Travis
# so, we just build it without brew http://mybyways.com/blog/compiling-wine-from-scratch-on-macos-with-retina-mode
# also, we build very minimal wine (~ 15 MB compressed)

WINE_VERSION=2.0.2
LIBPNG_VERSION=1.6.32
# 2.8.1 leads to error - https://forums.gentoo.org/viewtopic-p-8119832.html
FREETYPE_VERSION=2.8

rm -rf /tmp/wine
mkdir /tmp/wine
cd /tmp/wine
mkdir usr
mkdir usr/lib
mkdir usr/bin
mkdir usr/include

export TARGET=$(PWD)
export CPPFLAGS="-I$TARGET/usr/include"
export CFLAGS="-O3 -arch i386 -m32 -I$TARGET/usr/include"
export CXXFLAGS="$CFLAGS "
export LDFLAGS=" -arch i386 -L$TARGET/usr/lib"
export PATH="$TARGET/usr/bin:$PATH"
export PKG_CONFIG_PATH="$TARGET/usr/lib/pkgconfig"

cd ..

rm -rf jpeg-9b
curl -L http://ijg.org/files/jpegsrc.v9b.tar.gz | tar xz
cd jpeg-9b
./configure --prefix=$TARGET/usr
make install
cd ..

rm -rf libpng-*
curl -L http://downloads.sourceforge.net/project/libpng/libpng16/$LIBPNG_VERSION/libpng-$LIBPNG_VERSION.tar.gz | tar xz
cd libpng-$LIBPNG_VERSION
./configure --prefix=$TARGET/usr
make install
cd ..

rm -rf freetype-*
curl -L http://download.savannah.gnu.org/releases/freetype/freetype-$FREETYPE_VERSION.tar.gz | tar xz
cd freetype-$FREETYPE_VERSION
./configure --prefix=$TARGET/usr
make -j9
make install
cd ..

rm -rf wine-*
#curl https://dl.winehq.org/wine/source/2.x/wine-$WINE_VERSION.tar.xz | tar xz
curl https://dl.winehq.org/wine/source/2.0/wine-$WINE_VERSION.tar.xz | tar xz
cd wine-$WINE_VERSION
./configure --prefix=$TARGET/usr --disable-win64 --disable-win16 --without-x
make -j9
make install

cd ../wine/usr

# prepare wine home
WINEPREFIX=/tmp/wine/usr/wine-home ./bin/wineboot --init

unlink bin/widl
unlink bin/wrc
unlink bin/wmc

rm -rf share/man

rm -rf wine-home/drive_c/windows/Installer
rm -rf wine-home/drive_c/windows/Microsoft.NET
rm -rf wine-home/drive_c/windows/mono
rm -rf wine-home/drive_c/windows/system32/gecko
rm -rf wine-home/drive_c/windows/syswow64/gecko