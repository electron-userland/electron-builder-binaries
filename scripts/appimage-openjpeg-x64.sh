#!/usr/bin/env bash
set -ex

BASEDIR=$(cd "$(dirname "$0")/.." && pwd)
cd $BASEDIR
OUTPUT_DIR=$BASEDIR/AppImage/linux-x64
mkdir -p $OUTPUT_DIR

# get openjpg
rm -rf /tmp/openjpeg
mkdir /tmp/openjpeg
curl -L https://github.com/uclouvain/openjpeg/releases/download/v2.5.3/openjpeg-v2.5.3-linux-x86_64.tar.gz | tar -xz -C /tmp/openjpeg
mkdir -p $OUTPUT_DIR/lib/openjpeg-2.5
cp -a /tmp/openjpeg/openjpeg-v2.5.3-linux-x86_64/bin/* $OUTPUT_DIR/
cp -a /tmp/openjpeg/openjpeg-v2.5.3-linux-x86_64/lib/cmake/openjpeg-2.5 $OUTPUT_DIR/lib/openjpeg-2.5
cp -a /tmp/openjpeg/openjpeg-v2.5.3-linux-x86_64/lib/libopenjp2.* $OUTPUT_DIR/lib/
cp -a /tmp/openjpeg/openjpeg-v2.5.3-linux-x86_64/lib/pkgconfig $OUTPUT_DIR/lib
rm -rf /tmp/openjpeg
