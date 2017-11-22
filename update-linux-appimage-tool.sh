#!/usr/bin/env bash

BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd /tmp
rm -rf appimagetool
mkdir appimagetool
cd appimagetool
curl -L https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-i686.AppImage -o tool
chmod +x tool
docker run --rm -v ${PWD}:/project i386/ubuntu:xenial /bin/bash -c "cd /project && ./tool --appimage-extract"
cp squashfs-root/usr/bin/* $BASEDIR/AppImage/linux-ia32/
unlink $BASEDIR/AppImage/linux-ia32/zsyncmake

rm -rf appimagetool
mkdir appimagetool
cd appimagetool
curl -L https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage -o tool
chmod +x tool
docker run --rm -v ${PWD}:/project buildpack-deps:xenial-curl /bin/bash -c "cd /project && ./tool --appimage-extract"
cp squashfs-root/usr/bin/* $BASEDIR/AppImage/linux-x64/
unlink $BASEDIR/AppImage/linux-x64/zsyncmake