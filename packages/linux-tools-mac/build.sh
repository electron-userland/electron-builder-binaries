#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
OUTPUT_DIR="${ROOT}/out/linux-tools-mac"
ARCH="$(uname -m)"

rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🏗️  Building linux-tools-mac for ${ARCH}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash "$ROOT/assets/build-mac.sh" \
    --arch "$ARCH" \
    --output-dir "$OUTPUT_DIR" \
    --root "$ROOT"
