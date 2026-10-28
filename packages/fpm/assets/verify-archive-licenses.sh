#!/usr/bin/env bash
# Runs the license guard (scripts/verify-licenses.sh) on built fpm archives: extracts each .7z into its own empty
# temporary directory and checks that every binary in it is covered by LICENSES/MANIFEST.tsv.
#
#   verify-archive-licenses.sh <archive.7z>...
#
# Exits non-zero if an archive cannot be extracted or fails the check.
set -euo pipefail

CWD=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
VERIFY_LICENSES="${VERIFY_LICENSES:-$CWD/../../../scripts/verify-licenses.sh}"

if [ $# -eq 0 ]; then
    echo "Usage: $0 <archive.7z>..." >&2
    exit 2
fi
[ -f "$VERIFY_LICENSES" ] || { echo "❌ License guard not found: $VERIFY_LICENSES" >&2; exit 2; }

SEVEN_ZIP="$(command -v 7zz || command -v 7za || command -v 7z || true)"
[ -n "$SEVEN_ZIP" ] || { echo "❌ 7-Zip (7zz, 7za or 7z) is needed to extract the archives" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/fpm-licenses.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

failed=0
n=0
for archive in "$@"; do
    n=$((n + 1))
    dir="$WORK/$n"
    mkdir "$dir"
    echo "📦 $(basename "$archive")"
    "$SEVEN_ZIP" x -bd -y -o"$dir" "$archive" >/dev/null
    if ! bash "$VERIFY_LICENSES" "$dir"; then
        failed=1
    fi
    rm -rf "$dir"
done
exit "$failed"
