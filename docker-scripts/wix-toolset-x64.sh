#!/usr/bin/env bash
set -ex

BASEDIR=$(cd "$(dirname "$0")/.." && pwd)
cd $BASEDIR
OUTPUT_DIR=$BASEDIR/wix
rm -rf $OUTPUT_DIR
mkdir -p $OUTPUT_DIR

VERSION=3.14.1

# Download the latest version of WiX Toolset (Windows)
curl -L 'https://github.com/wixtoolset/wix3/releases/download/wix3141rtm/wix314-binaries.zip' > a.zip
7za x a.zip -oa
unlink a.zip
cp -a a/* $OUTPUT_DIR
rm -rf a
rm -rf $OUTPUT_DIR/sdk
rm -rf $OUTPUT_DIR/doc

echo $VERSION > $OUTPUT_DIR/VERSION