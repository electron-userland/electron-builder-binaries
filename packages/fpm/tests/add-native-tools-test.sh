#!/usr/bin/env bash
# Self-test for packages/fpm/assets/add-native-tools.sh: merges a tiny native-tools stage (whose "binaries" are just
# magic bytes) into a tiny fpm archive and checks the layout, the merged LICENSES/ and that a collision or a binary
# without a license fails. The license "texts" are placeholders for the test only. Portable bash: Linux and macOS.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADD="$HERE/../assets/add-native-tools.sh"
export VERIFY_LICENSES="$HERE/../../../scripts/verify-licenses.sh"
SEVEN_ZIP="$(command -v 7za || command -v 7zz || command -v 7z || true)"
if [ -z "$SEVEN_ZIP" ]; then
    echo "ℹ️  7-Zip not found: skipping the add-native-tools tests"
    exit 0
fi
WORK="$(mktemp -d "${TMPDIR:-/tmp}/add-native-tools-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
RUBY_DIR=ruby-3.4.12-portable
TAB=$(printf '\t')

elf()     { mkdir -p "$(dirname "$1")"; printf '\177ELF\002\001\001\000padding' > "$1"; chmod 755 "$1"; }
fixture() { mkdir -p "$(dirname "$1")"; printf 'test fixture: %s\n' "${2:-license text}" > "$1"; }

# fpm_archive <archive>: a minimal fpm toolset with a zlib component shared with the stage
fpm_archive() {
    local d="$WORK/fpm-src"
    rm -rf "$d" "$1"
    mkdir -p "$d"
    printf '#!/usr/bin/env bash\n' > "$d/fpm"
    chmod 755 "$d/fpm"
    printf 'ruby 3.4.12\n' > "$d/VERSION.txt"
    elf "$d/$RUBY_DIR/bin/ruby"
    elf "$d/$RUBY_DIR/lib/libz.so.1"
    fixture "$d/LICENSES/ruby/COPYING" "ruby"
    fixture "$d/LICENSES/zlib/copyright" "zlib (debian)"
    fixture "$d/LICENSES/zlib/SOURCE.txt" "zlib from debian"
    printf '# header\n%s\truby\n%s\tzlib\n' "$RUBY_DIR/bin/ruby" "$RUBY_DIR/lib/libz.so.1" > "$d/LICENSES/MANIFEST.tsv"
    (cd "$d" && "$SEVEN_ZIP" a -bd "$1" ./* >/dev/null)
}

# native_stage <dir>
native_stage() {
    local s="$1"
    rm -rf "$s"
    elf "$s/bin/xz"
    printf '#!/bin/sh\n' > "$s/bin/rpmbuild"
    elf "$s/libexec/rpmbuild"
    elf "$s/lib/libz.so.1"
    fixture "$s/share/misc/magic.mgc" "not a binary"
    fixture "$s/LICENSES/xz-utils/COPYING.0BSD" "xz"
    fixture "$s/LICENSES/rpm/COPYING" "rpm"
    fixture "$s/LICENSES/zlib/README" "zlib (almalinux)"
    fixture "$s/LICENSES/zlib/SOURCE.txt" "zlib from almalinux"
    fixture "$s/LICENSES/zlib/copyright" "a different zlib copyright"
    printf 'bin/xz\txz-utils\nlib/libz.so.1\tzlib\nlibexec/rpmbuild\trpm\n' > "$s/LICENSES/MANIFEST.tsv"
    printf 'xz: 5.8.4\n' > "$s/VERSION.txt"
}

failures=0
fail() {
    echo "❌ $1"
    [ -z "${OUT:-}" ] || printf '%s\n' "$OUT" | sed 's/^/     /'
    failures=$((failures + 1))
}

ARCHIVE="$WORK/out/fpm-test.7z"
STAGE="$WORK/stage"
mkdir -p "$WORK/out"

# --- merge ---
fpm_archive "$ARCHIVE"
native_stage "$STAGE"
if OUT=$(bash "$ADD" "$ARCHIVE" "$STAGE" 2>&1); then
    X="$WORK/x"
    rm -rf "$X"
    "$SEVEN_ZIP" x -bd -y -o"$X" "$ARCHIVE" >/dev/null
    for f in fpm bin/xz bin/rpmbuild libexec/rpmbuild lib/libz.so.1 share/misc/magic.mgc "$RUBY_DIR/bin/ruby" \
        LICENSES/xz-utils/COPYING.0BSD LICENSES/rpm/COPYING LICENSES/zlib/README LICENSES/zlib/copyright \
        LICENSES/zlib/copyright.native LICENSES/ruby/COPYING; do
        [ -e "$X/$f" ] || { OUT=$(cd "$X" && find . | sort); fail "merge: $f missing"; }
    done
    [ -x "$X/bin/xz" ] || fail "merge: bin/xz lost its executable bit"
    grep -q 'zlib from debian' "$X/LICENSES/zlib/SOURCE.txt" && grep -q 'zlib from almalinux' "$X/LICENSES/zlib/SOURCE.txt" ||
        { OUT=$(cat "$X/LICENSES/zlib/SOURCE.txt"); fail "merge: zlib SOURCE.txt not appended"; }
    for line in "bin/xz${TAB}xz-utils" "lib/libz.so.1${TAB}zlib" "libexec/rpmbuild${TAB}rpm" "$RUBY_DIR/bin/ruby${TAB}ruby"; do
        grep -qxF "$line" "$X/LICENSES/MANIFEST.tsv" || { OUT=$(cat "$X/LICENSES/MANIFEST.tsv"); fail "merge: MANIFEST.tsv lacks $line"; }
    done
    grep -q 'xz: 5.8.4' "$X/VERSION.txt" && grep -q 'ruby 3.4.12' "$X/VERSION.txt" || { OUT=$(cat "$X/VERSION.txt"); fail "merge: VERSION.txt"; }
    [ "$failures" -gt 0 ] || echo "✓ merge: native tools, licenses and VERSION.txt added to the archive"
else
    fail "merge: add-native-tools.sh failed"
fi

# --- a stage entry that already exists in the bundle ---
fpm_archive "$ARCHIVE"
native_stage "$STAGE"
elf "$STAGE/$RUBY_DIR/bin/ruby"
if OUT=$(bash "$ADD" "$ARCHIVE" "$STAGE" 2>&1); then
    fail "collision: expected a failure"
elif printf '%s\n' "$OUT" | grep -q "$RUBY_DIR already exists in the fpm bundle"; then
    echo "✓ collision: an existing bundle entry is never overwritten"
else
    fail "collision: unexpected error"
fi

# --- a binary without a license ---
fpm_archive "$ARCHIVE"
native_stage "$STAGE"
elf "$STAGE/lib/libunknown.so.1"
if OUT=$(bash "$ADD" "$ARCHIVE" "$STAGE" 2>&1); then
    fail "license: expected a failure"
elif printf '%s\n' "$OUT" | grep -q "lib/libunknown.so.1"; then
    echo "✓ license: a native binary without a license fails"
else
    fail "license: unexpected error"
fi

echo ""
if [ "$failures" -gt 0 ]; then
    echo "❌ $failures add-native-tools test(s) failed"
    exit 1
fi
echo "✓ All add-native-tools tests passed"
