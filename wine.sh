#!/usr/bin/env bash

# custom homebrew prefix and DYLD_FALLBACK_LIBRARY_PATH doesn't work due to unknown reasons on Travis
# homebrew bottle and DYLD_FALLBACK_LIBRARY_PATH doesn't work due to not found library on Travis
# so, we just build it without brew http://mybyways.com/blog/compiling-wine-from-scratch-on-macos-with-retina-mode

WINE_VERSION=2.0.1
LIBPNG_VERSION=1.6.29
FREETYPE_VERSION=2.8

mkdir ~/Downloads/wine
cd ~/Downloads/wine
mkdir usr
mkdir usr/lib
mkdir usr/bin
mkdir usr/include

export TARGET=$(PWD)
export CPPFLAGS="-I$TARGET/usr/include"
export CFLAGS="-O2 -arch i386 -m32 -I$TARGET/usr/include"
export CXXFLAGS="$CFLAGS "
export LDFLAGS=" -arch i386 -L$TARGET/usr/lib"
export PATH="$TARGET/usr/bin:$PATH"
export PKG_CONFIG_PATH="$TARGET/usr/lib/pkgconfig"

cd ..

curl -L http://ijg.org/files/jpegsrc.v9b.tar.gz | tar xz
cd jpeg-9b
./configure --prefix=$TARGET/usr
make install
cd ..

curl -L http://downloads.sourceforge.net/project/libpng/libpng16/$LIBPNG_VERSION/libpng-$LIBPNG_VERSION.tar.gz | tar xz
cd libpng-$LIBPNG_VERSION
./configure --prefix=$TARGET/usr
make install
cd ..

curl -L http://download.savannah.gnu.org/releases/freetype/freetype-$FREETYPE_VERSION.tar.gz | tar xz
cd freetype-$FREETYPE_VERSION
./configure --prefix=$TARGET/usr
make install
cd ..

curl http://dl.winehq.org/wine/source/2.0/wine-$WINE_VERSION.tar.xz | tar xz
cd wine-$WINE_VERSION
./configure --prefix=$TARGET/usr --disable-win64 --without-x
make install
cd ..

# prepare wine home
WINEPREFIX=$HOME/Downloads/wine/wine-home wine/bin/wineboot --init

unlink bin/widl
unlink bin/wrc
unlink bin/wmc

rm -rf share/man

rm -rf wine-home/drive_c/windows/Installer
rm -rf wine-home/drive_c/windows/Microsoft.NET
rm -rf wine-home/drive_c/windows/mono
rm -rf wine-home/drive_c/windows/system32/gecko
rm -rf wine-home/drive_c/windows/syswow64/gecko