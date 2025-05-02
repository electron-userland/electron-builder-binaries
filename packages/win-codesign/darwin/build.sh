#!/usr/bin/env bash
set -e

brew install libgsf osslsigncode

BASEDIR=$(cd "$(dirname "$0")/../../.." && pwd)
cd $BASEDIR
OUTPUT_DIR=$BASEDIR/out/winCodeSign/darwin
rm -rf $OUTPUT_DIR
mkdir -p $OUTPUT_DIR

cp -a /opt/homebrew/bin/osslsigncode $OUTPUT_DIR/