#!/usr/bin/env bash

# to build AppImage on macOS:
# 1. `brew install libtool`
# 2. `brew install Caskroom/cask/osxfuse`

BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/AppImage"

NAME=appimage
version=`cat $BASEDIR/version.txt`
archiveFileName=$NAME-$version.7z
archiveFile=$BASEDIR/../out/$archiveFileName
rm -f $archiveFile

cd $BASEDIR
7za a -m0=lzma2 -mx=9 -mfb=64 -md=64m -ms=on $archiveFile .
cd ..

if [ -z "$GITHUB_TOKEN" ] ; then
  SEC=`security find-generic-password -l GH_TOKEN -g 2>&1`
  export GITHUB_TOKEN=`echo "$SEC" | grep "password" | cut -d \" -f 2`
fi

CHECKSUM=$(shasum -a 512 $archiveFile | xxd -r -p | base64)
$BASEDIR/../github-release electron-userland/electron-builder-binaries $NAME-$version master "Sha512: $CHECKSUM" $archiveFile