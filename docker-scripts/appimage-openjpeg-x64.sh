#!/usr/bin/env bash
set -ex

BASEDIR=$(cd "$(dirname "$0")/.." && pwd)
cd $BASEDIR
OUTPUT_DIR=$BASEDIR/AppImage/linux-x64
mkdir -p $OUTPUT_DIR

VERSION=2.5.3

# Download the latest version of OpenJPEG (Linux)
rm -rf /tmp/openjpeg
mkdir /tmp/openjpeg
curl -L https://github.com/uclouvain/openjpeg/releases/download/v$VERSION/openjpeg-v$VERSION-linux-x86_64.tar.gz | tar -xz -C /tmp/openjpeg
mkdir -p $OUTPUT_DIR/lib/openjpeg-2.5
cp -a /tmp/openjpeg/openjpeg-v$VERSION-linux-x86_64/bin/* $OUTPUT_DIR/
cp -a /tmp/openjpeg/openjpeg-v$VERSION-linux-x86_64/lib/cmake/openjpeg-2.5 $OUTPUT_DIR/lib/openjpeg-2.5
cp -a /tmp/openjpeg/openjpeg-v$VERSION-linux-x86_64/lib/libopenjp2.* $OUTPUT_DIR/lib/
cp -a /tmp/openjpeg/openjpeg-v$VERSION-linux-x86_64/lib/pkgconfig $OUTPUT_DIR/lib
rm -rf /tmp/openjpeg

echo $VERSION > $OUTPUT_DIR/VERSION
