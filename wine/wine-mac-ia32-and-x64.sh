#!/usr/bin/env bash
set -ex

# Issues with FreeType (works, but list of warnings), in any case 1) we need to bundle also Net framework as part of wine home 2) no need to ia32+x64, to reduce size, the only arch should be used
# So, for now our existing wine 2.0.3 is used on macOS

TMP_WINE=/tmp/wine-stage-all
rm -rf $TMP_WINE
mkdir -p $TMP_WINE/wine
cd $TMP_WINE/wine

WINE_VERSION=5.0
curl https://dl.winehq.org/wine-builds/macosx/pool/portable-winehq-stable-$WINE_VERSION-osx64.tar.gz | tar xz

cd $TMP_WINE/wine/usr

unlink bin/wine

# prepare wine home
WINEPREFIX=$TMP_WINE/wine/usr/wine-home WINEARCH=win64 ./bin/wineboot --init

rm -rf share/man
rm -rf share/doc
rm -rf share/gtk-doc
rm -rf include

rm -rf wine-home/drive_c/windows/Installer
rm -rf wine-home/drive_c/windows/Microsoft.NET
rm -rf wine-home/drive_c/windows/mono
rm -rf wine-home/drive_c/windows/system32/gecko
rm -rf wine-home/drive_c/windows/syswow64/gecko
rm -rf wine-home/drive_c/windows/logs
rm -rf wine-home/drive_c/windows/inf