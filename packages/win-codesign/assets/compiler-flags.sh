#!/usr/bin/env bash
# assets/compiler-flags.sh
set -euo pipefail

usage() {
    echo "Usage: $0 --arch <amd64|i386|arm64>" >&2
    exit 1
}

ARCH="amd64"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch) ARCH="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown argument: $1" >&2; usage ;;
    esac
done

# Default: native build
CMAKE_FLAGS=""

case "$ARCH" in
  amd64|x86_64)
    # No special flags needed for native 64-bit build
    CMAKE_FLAGS=""
    ;;

  i386)
    # Cross-compile for 32-bit Intel
    CMAKE_FLAGS="-DCMAKE_C_FLAGS=-m32 \
                 -DCMAKE_CXX_FLAGS=-m32 \
                 -DCMAKE_EXE_LINKER_FLAGS=-m32 \
                 -DCMAKE_SHARED_LINKER_FLAGS=-m32"
    ;;

  arm64|aarch64)
    # Cross-compile for ARM64
    CMAKE_FLAGS="-DCMAKE_SYSTEM_NAME=Linux \
                 -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
                 -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc \
                 -DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++ \
                 -DCMAKE_FIND_ROOT_PATH=/usr/aarch64-linux-gnu \
                 -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
                 -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
                 -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY"
    ;;

  *)
    echo "Unknown architecture: $ARCH" >&2
    exit 1
    ;;
esac

echo "$CMAKE_FLAGS"
