#!/bin/bash
set -euo pipefail

# CONFIG
PYTHON_VERSION="3.14.2"
# https://github.com/dmgbuild/dmgbuild
# base: v1.6.7
DMGBUILD_VERSION_OR_HASH="9614277" # commit 9614277f759768cfc156a3493dd2b60fae7d63d5

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

OUTPUT_DIR="${ROOT}/out/dmg-builder"

rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

# Default to current architecture
# can also be space-separated list, e.g. "x86_64 arm64"
ARCHS=${1:-"$(uname -m)"}

for ARCH in $ARCHS; do
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🏗️  Building Python runtime for ${ARCH}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    bash "$ROOT/assets/build-python-runtime.sh" "$ROOT" "$OUTPUT_DIR" $PYTHON_VERSION $DMGBUILD_VERSION_OR_HASH "-" "${ARCH}"
done