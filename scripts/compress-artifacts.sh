#!/usr/bin/env bash
set -exuo pipefail
shopt -s nullglob

ROOT_DIR=$(cd "$( dirname -- "$BASH_SOURCE"; )/.." && pwd)

BUILD_OUT_DIR=$ROOT_DIR/out
ARTIFACTS_DIR=$ROOT_DIR/artifacts-staging
mkdir -p "$ARTIFACTS_DIR" "$BUILD_OUT_DIR"

for FILEPATH in "$BUILD_OUT_DIR"/*; do
  NAME="$(basename "$FILEPATH")"
  DESTINATION_DIR="$ARTIFACTS_DIR/$NAME"

  rm -rf "$DESTINATION_DIR"
  cp -a "$FILEPATH" "$DESTINATION_DIR"
done
