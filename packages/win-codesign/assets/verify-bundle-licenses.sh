#!/usr/bin/env bash
# Runs the shared license guard (scripts/verify-licenses.sh) on win-codesign bundles: every binary must be listed in
# LICENSES/MANIFEST.tsv with its license files in LICENSES/<component>/, or exempted in LICENSES/EXEMPT.tsv.
#
# Run: bash packages/win-codesign/assets/verify-bundle-licenses.sh <bundle.zip | bundle-dir>...
# Exits 1 when a bundle fails the check, 2 on usage errors.
set -euo pipefail

if [ $# -eq 0 ]; then
    echo "Usage: $0 <bundle.zip | bundle-dir>..." >&2
    exit 2
fi

# shellcheck source=licenses.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/licenses.sh"

license_verify "$@"
