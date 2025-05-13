#!/bin/bash

set -euo pipefail

BASEDIR=$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)
if [[ ${BASEDIR: -1} == "/" ]]; then
    BASEDIR="."
fi
echo "🎯 Base directory: $BASEDIR"
# Check if the script is running from the correct directory
if [[ ! -d "$BASEDIR/assets" ]]; then
    echo "Please run this script from the fpm package directory."
    exit 1
fi
OUTPUT_DIR="$BASEDIR/out/fpm"
mkdir -p "$OUTPUT_DIR"

# ===== Configuration =====
RUBY_VERSION=$RUBY_VERSION # 3.4.3
# Check if RUBY_VERSION is set
if [ -z "$RUBY_VERSION" ]; then
    echo "RUBY_VERSION is not set. Please set it to the desired Ruby version."
    exit 1
fi
SOURCE_DIR="/tmp/ruby-source"
INSTALL_DIR="/tmp/ruby-install"
RUBY_DIR_NAME="ruby-$RUBY_VERSION-portable"
RUBY_PREFIX="$INSTALL_DIR/$RUBY_DIR_NAME"