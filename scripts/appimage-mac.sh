#!/usr/bin/env bash
set -ex

BASEDIR=$(cd "$(dirname "$0")/.." && pwd)
cd $BASEDIR
OUT_DIR=$BASEDIR/out/AppImage
rm -rf $OUT_DIR
mkdir -p $OUT_DIR/darwin

OUTPUT_DIR=/tmp/appimage-mac
rm -rf $OUTPUT_DIR
mkdir -p $OUTPUT_DIR/darwin

# Download the latest versions for desktop-file-validate and mksquashfs (macOS)
brew install desktop-file-utils squashfs
cp -aL $(which desktop-file-validate) $OUTPUT_DIR/darwin/desktop-file-validate
cp -aL $(which mksquashfs) $OUTPUT_DIR/darwin/mksquashfs

curl -L https://github.com/AppImage/type2-runtime/releases/download/continuous/runtime-aarch64 > $OUTPUT_DIR/runtime-arm64
curl -L https://github.com/AppImage/type2-runtime/releases/download/continuous/runtime-armhf > $OUTPUT_DIR/runtime-armv7l
curl -L https://github.com/AppImage/type2-runtime/releases/download/continuous/runtime-i686 > $OUTPUT_DIR/runtime-ia32
curl -L https://github.com/AppImage/type2-runtime/releases/download/continuous/runtime-x86_64 > $OUTPUT_DIR/runtime-x64

cp -aL $OUTPUT_DIR/* $OUT_DIR
rm -rf $OUTPUT_DIR