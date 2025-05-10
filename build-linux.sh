#!/usr/bin/env bash
set -e

CWD=$(cd "$(dirname "$0")" && pwd)

# fpm
export ARCH=${ARCH:-$(uname -m)}
export OS_TARGET="linux"
bash "$CWD/packages/fpm/build.sh"
