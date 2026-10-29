#!/usr/bin/env bash
# Adds the native tools staged by build-native-{linux,mac}.sh to a built fpm toolset archive, in place:
#   - the stage's bin/, libexec/, lib/, share/ go to the bundle root, next to fpm, ruby.env and
#     ruby-*-portable/ (an entry that already exists in the bundle is an error, never overwritten)
#   - LICENSES/<component>/ are merged: a new component is copied; for a component the bundle already
#     has (e.g. zlib, used by Ruby and by rpm), identical files are kept once, SOURCE.txt is appended to,
#     and a different file with the same name is added as <name>.native
#   - LICENSES/MANIFEST.tsv lines are appended, VERSION.txt is appended to
# then checks every binary's license (scripts/verify-licenses.sh) and recompresses the archive.
#
# Usage: add-native-tools.sh <fpm-archive.7z> <native-stage-dir>
set -euo pipefail

CWD=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
VERIFY_LICENSES="${VERIFY_LICENSES:-$CWD/../../../scripts/verify-licenses.sh}"

[ $# -eq 2 ] || { echo "Usage: $0 <fpm-archive.7z> <native-stage-dir>" >&2; exit 2; }
ARCHIVE=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
STAGE=$(cd "$2" && pwd)

die() {
    echo "❌ $*" >&2
    exit 1
}

[ -f "$ARCHIVE" ] || die "archive not found: $ARCHIVE"
[ -f "$STAGE/LICENSES/MANIFEST.tsv" ] || die "$STAGE/LICENSES/MANIFEST.tsv is missing"
[ -x "$STAGE/bin/xz" ] || die "$STAGE/bin/xz is missing"
SEVEN_ZIP="$(command -v 7za || command -v 7zz || command -v 7z || true)"
[ -n "$SEVEN_ZIP" ] || die "7-Zip (7za, 7zz or 7z) is needed"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/fpm-native-merge.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
BUNDLE="$WORK/bundle"
mkdir "$BUNDLE"
"$SEVEN_ZIP" x -bd -y -o"$BUNDLE" "$ARCHIVE" >/dev/null
[ -x "$BUNDLE/fpm" ] && [ -f "$BUNDLE/LICENSES/MANIFEST.tsv" ] || die "$(basename "$ARCHIVE") is not an fpm toolset (no fpm or LICENSES/MANIFEST.tsv)"

echo "🧩 Adding native tools to $(basename "$ARCHIVE")"
for entry in "$STAGE"/*; do
    name=$(basename "$entry")
    case "$name" in LICENSES | VERSION.txt) continue ;; esac
    [ ! -e "$BUNDLE/$name" ] || die "$name already exists in the fpm bundle; refusing to overwrite it"
    cp -a "$entry" "$BUNDLE/$name"
    echo "  + $name/"
done

for component_dir in "$STAGE"/LICENSES/*/; do
    component_dir="${component_dir%/}"
    component=$(basename "$component_dir")
    dest="$BUNDLE/LICENSES/$component"
    if [ ! -e "$dest" ]; then
        cp -a "$component_dir" "$dest"
        continue
    fi
    echo "  📄 LICENSES/$component: shared with the Ruby bundle"
    for f in "$component_dir"/*; do
        [ -f "$f" ] || die "LICENSES/$component/$(basename "$f"): only files are supported in a shared component"
        name=$(basename "$f")
        if [ ! -e "$dest/$name" ]; then
            cp "$f" "$dest/$name"
        elif cmp -s "$f" "$dest/$name"; then
            :
        elif [ "$name" = "SOURCE.txt" ]; then
            cat "$f" >>"$dest/SOURCE.txt"
        else
            [ ! -e "$dest/$name.native" ] || die "LICENSES/$component/$name.native already exists"
            cp "$f" "$dest/$name.native"
        fi
    done
done

{
    cat "$BUNDLE/LICENSES/MANIFEST.tsv"
    echo "# Native tools (bin/), added by packages/fpm/assets/add-native-tools.sh"
    grep -v '^#' "$STAGE/LICENSES/MANIFEST.tsv" | sort -u
} >"$WORK/MANIFEST.tsv"
mv "$WORK/MANIFEST.tsv" "$BUNDLE/LICENSES/MANIFEST.tsv"

if [ -f "$STAGE/VERSION.txt" ]; then
    cat "$STAGE/VERSION.txt" >>"$BUNDLE/VERSION.txt"
fi

bash "$VERIFY_LICENSES" "$BUNDLE"

echo "🔨 Recompressing $(basename "$ARCHIVE")"
before=$(wc -c <"$ARCHIVE" | tr -d ' ')
rm -f "$ARCHIVE"
(cd "$BUNDLE" && "$SEVEN_ZIP" a -bd -mx=9 -mfb=64 "$ARCHIVE" ./* >/dev/null)
after=$(wc -c <"$ARCHIVE" | tr -d ' ')
echo "📦 $(basename "$ARCHIVE"): $before -> $after bytes"
