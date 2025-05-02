#!/usr/bin/env bash
set -ex


BASEDIR=$(cd "$(dirname "$0")/.." && pwd)
cd $BASEDIR
OUTPUT_DIR=$BASEDIR/win-codesign

OSSLSIGNCODE_VERSION=${OSSLSIGNCODE_VERSION:-2.9}

rm -rf a $OUTPUT_DIR
mkdir -p $OUTPUT_DIR
curl -L https://github.com/mtrojnar/osslsigncode/releases/download/$OSSLSIGNCODE_VERSION/osslsigncode-$OSSLSIGNCODE_VERSION-macOS.zip > a.zip
7za x a.zip -oa
cp -a a/bin $OUTPUT_DIR/darwin
echo $OSSLSIGNCODE_VERSION > $OUTPUT_DIR/darwin/VERSION
chmod +x $OUTPUT_DIR/darwin/osslsigncode
rm -rf a a.zip


RCEDIT_VERSION=${RCEDIT_VERSION:-2.2.0}

curl -L https://github.com/electron/rcedit/releases/download/v$RCEDIT_VERSION/rcedit-x64.exe > $OUTPUT_DIR/rcedit-x64.exe
curl -L https://github.com/electron/rcedit/releases/download/v$RCEDIT_VERSION/rcedit-x86.exe > $OUTPUT_DIR/rcedit-ia32.exe
echo $RCEDIT_VERSION > $OUTPUT_DIR/VERSION
