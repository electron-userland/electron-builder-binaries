#!/usr/bin/env bash
set -ex

BASEDIR=$(cd "$(dirname "$0")/.." && pwd)
cd $BASEDIR
DIR=$BASEDIR/Squirrel.Windows

OUTPUT_DIR=/tmp/squirrel
rm -rf $OUTPUT_DIR
mkdir $OUTPUT_DIR

VERSION=1.9.1

# Download the latest version of NSIS (Windows)
curl -L https://github.com/Squirrel/Squirrel.Windows/releases/download/$VERSION/Squirrel.Windows-$VERSION.zip > squirrel.zip
unzip -o squirrel.zip -d squirrel
cp -a squirrel/* $OUTPUT_DIR/
rm -rf squirrel.zip squirrel

echo $VERSION > $OUTPUT_DIR/VERSION

rm -rf $DIR
mkdir $DIR
cp -a $OUTPUT_DIR/* $DIR