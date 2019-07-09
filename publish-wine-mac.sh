#!/usr/bin/env bash
set -e

BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -z "$GITHUB_TOKEN" ] ; then
  SEC=`security find-generic-password -l GH_TOKEN -g 2>&1`
  export GITHUB_TOKEN=`echo "$SEC" | grep "password" | cut -d \" -f 2`
fi

VERSION=4.0.1-mac
rm -f /tmp/wine-$VERSION.7z
cd /tmp/wine-stage/wine/usr
$BASEDIR/7za a -m0=lzma2 -mx=9 -mfb=64 -md=256m -ms=on /tmp/wine-$VERSION.7z .
CHECKSUM=$(shasum -a 512 /tmp/wine-$VERSION.7z | xxd -r -p | base64)
$BASEDIR/github-release electron-userland/electron-builder-binaries wine-$VERSION master "Sha512: $CHECKSUM" /tmp/wine-$VERSION.7z