#!/usr/bin/env bash
set -ex

CWD=$(cd "$(dirname "$0")" && pwd)

# fpm
export OS_TARGET="darwin"
bash "$CWD/packages/fpm/build.sh"