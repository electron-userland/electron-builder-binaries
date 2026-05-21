#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
OUTPUT_DIR="${ROOT}/out/linux-tools"
ARCHS="$(uname -m)"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch) ARCHS="$2"; shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

for ARCH in $ARCHS; do
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🏗️  Building linux-tools for ${ARCH}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    bash "$ROOT/assets/build-mac.sh" \
        --arch "$ARCH" \
        --output-dir "$OUTPUT_DIR" \
        --root "$ROOT"
done
