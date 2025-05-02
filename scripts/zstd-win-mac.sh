#!/usr/bin/env bash
set -ex

BASEDIR=$(cd "$(dirname "$0")/.." && pwd)
cd $BASEDIR
OUTPUT_DIR=$BASEDIR/out/zstd
mkdir -p $OUTPUT_DIR

TMP_DIR=/tmp/zstd
rm -rf $TMP_DIR
mkdir $TMP_DIR
cd $TMP_DIR

VERSION=1.5.0

mkdir -p "$OUTPUT_DIR/win-x64"
curl -L https://github.com/facebook/zstd/releases/download/v$VERSION/zstd-v$VERSION-win64.zip --output zstd-win64.zip
unzip zstd-win64.zip
cp -a zstd-v$VERSION-win64/zstd.exe "$OUTPUT_DIR/win-x64/zstd.exe"

mkdir -p "$OUTPUT_DIR/win-ia32"
curl -L https://github.com/facebook/zstd/releases/download/v$VERSION/zstd-v$VERSION-win32.zip --output zstd-win32.zip
unzip zstd-win32.zip
cp -a zstd-v$VERSION-win32/zstd.exe "$OUTPUT_DIR/win-ia32/zstd.exe"

# build on macOS
mkdir -p "$OUTPUT_DIR/mac"
git clone --depth 1 --branch v$VERSION https://github.com/facebook/zstd.git
cd zstd
make -j5
cp -a programs/zstd "$OUTPUT_DIR/mac/zstd"

rm -rf $TMP_DIR

echo $VERSION > $OUTPUT_DIR/VERSION
