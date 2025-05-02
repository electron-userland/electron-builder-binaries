#!/usr/bin/env bash
set -ex

BASE_DIR=$(cd "$(dirname "$0")/.." && pwd)
OUTPUT_DIR=$BASE_DIR/out/ran
mkdir -p "$OUTPUT_DIR/win32" "$OUTPUT_DIR/win64" "$OUTPUT_DIR/linux" "$OUTPUT_DIR/darwin"

TMP_DIR=/tmp/ran
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

VERSION=0.1.6

cd "$TMP_DIR"
curl -L https://github.com/m3ng9i/ran/releases/download/v$VERSION/ran_windows_386.exe.zip --output f.zip
unzip f.zip
cp ran_windows_386.exe "$OUTPUT_DIR/win32/ran.exe"
rm f.zip

curl -L https://github.com/m3ng9i/ran/releases/download/v$VERSION/ran_windows_amd64.exe.zip --output f.zip
unzip f.zip
cp ran_windows_amd64.exe "$OUTPUT_DIR/win64/ran.exe"
rm f.zip

curl -L https://github.com/m3ng9i/ran/releases/download/v$VERSION/ran_linux_amd64.zip --output f.zip
unzip f.zip
cp ran_linux_amd64 "$OUTPUT_DIR/linux/ran"
rm f.zip

curl -L https://github.com/m3ng9i/ran/releases/download/v$VERSION/ran_darwin_amd64.zip --output f.zip
unzip f.zip
cp ran_darwin_amd64 "$OUTPUT_DIR/darwin/ran"
rm f.zip
