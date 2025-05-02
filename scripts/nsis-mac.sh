#!/usr/bin/env bash
set -ex

BASEDIR=$(cd "$(dirname "$0")/.." && pwd)
cd $BASEDIR
OUT_DIR=$BASEDIR/out/nsis/mac
mkdir -p $OUT_DIR

OUTPUT_DIR=/tmp/nsis-mac
rm -rf $OUTPUT_DIR
mkdir $OUTPUT_DIR

VERSION=3.11

# Download the latest version of NSIS (macOS)
mkdir -p $OUTPUT_DIR/mac
brew tap nsis-dev/makensis
brew install makensis@$VERSION --with-large-strings --with-advanced-logging
cp -aL $(which makensis) $OUTPUT_DIR/makensis

echo $VERSION > $OUTPUT_DIR/VERSION

cp -a $OUTPUT_DIR/* $OUT_DIR
rm -rf $OUTPUT_DIR