#!/usr/bin/env bash
set -ex

BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

rm -rf /tmp/zstd
mkdir /tmp/zstd
cd /tmp/zstd

curl -L https://github.com/facebook/zstd/releases/download/v1.5.0/zstd-v1.5.0-win64.zip --output zstd-win64.zip
unzip zstd-win64.zip
cp zstd-v1.5.0-win64/zstd.exe "$BASEDIR/zstd/win-x64/zstd.exe"

curl -L https://github.com/facebook/zstd/releases/download/v1.5.0/zstd-v1.5.0-win32.zip --output zstd-win32.zip
unzip zstd-win32.zip
cp zstd-v1.5.0-win32/zstd.exe "$BASEDIR/zstd/win-ia32/zstd.exe"

# build on macOS
git clone --depth 1 --branch v1.5.0 https://github.com/facebook/zstd.git
cd zstd
make -j5
cp programs/zstd "$BASEDIR/zstd/mac/zstd"

cd /tmp/
rm -rf /tmp/zstd