#!/usr/bin/env bash
set -e

ROOT_DIR=$(cd "$( dirname -- "$BASH_SOURCE"; )/.." && pwd)
PACKAGE_PATH=$ROOT_DIR/packages
BUILD_OUT_DIR=$ROOT_DIR/out
mkdir -p "$BUILD_OUT_DIR"
ARTIFACTS_DIR=$ROOT_DIR/artifacts
mkdir -p "$ARTIFACTS_DIR"

hashArtifact()
{
    ARCHIVE_PATH=$1
    if [ ! -f "$ARCHIVE_PATH" ]; then
        echo "Artifact $ARCHIVE_NAME does not exist in $ARTIFACTS_DIR"
        exit 1
    fi
    CHECKSUM=$(shasum -a 512 "$ARCHIVE_PATH" | xxd -r -p | base64)
    EXPECTED="${2:-$CHECKSUM}"
    if [ "$CHECKSUM" != "$EXPECTED" ]; then
        echo "Checksum for $ARCHIVE_NAME does not match expected checksum"
        echo "Expected: $EXPECTED"
        echo "Actual: $CHECKSUM"
        exit 1
    elif [ ! "$2" ];then
        echo "Checksum for $ARCHIVE_NAME matches expected checksum"
    fi
    touch "$ARCHIVE_PATH.checksum.txt"
    echo "$ARCHIVE_NAME: $CHECKSUM" >> "$ARCHIVE_PATH.checksum.txt"
}

downloadArtifact()
{
    RELEASE_NAME=$1
    ARCHIVE_NAME="$2.7z"
    CHECKSUM=$3
    OUTPUT_PATH=$4
    OUTPUT_NAME="${5:-$2}.7z"
    curl -L https://github.com/electron-userland/electron-builder-binaries/releases/download/$RELEASE_NAME/$ARCHIVE_NAME > "$OUTPUT_PATH/$OUTPUT_NAME"
    hashArtifact "$OUTPUT_PATH/$OUTPUT_NAME" "$CHECKSUM"
}

compressArtifact()
{
    ARCHIVE_PATH="$1"
    PACKAGE_PATH="$2"
    DESTINATION="$BUILD_OUT_DIR/$ARCHIVE_PATH"
    rm -f "$DESTINATION"
    7za a -mx=9 -mfb=64 "$DESTINATION" "$PACKAGE_PATH"/*
    echo "$1 compressed to $DESTINATION"
    # hashArtifact "$DESTINATION"
}