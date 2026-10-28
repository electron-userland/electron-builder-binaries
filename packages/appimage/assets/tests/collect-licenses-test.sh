#!/usr/bin/env bash
# Tests for packages/appimage/assets/collect-licenses.sh (the LICENSES/ layout of the AppImage tools bundle) and the
# shared guard's verdict on bundles laid out with it. No network, Docker, dpkg or Homebrew needed: the package
# databases are fakes on PATH and file:// URLs stand in for downloads.
# Portable bash: Linux and macOS (bash 3.2).
# Single-quoted scripts below are run by lic / bash -c, which expand them:
# shellcheck disable=SC2016
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS="$HERE/.."
VERIFY="$HERE/../../../../scripts/verify-licenses.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/appimage-licenses-test.XXXXXX")"
WORK="$(cd "$WORK" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

failures=0
pass() { echo "✅ $1"; }
fail() { echo "❌ $1"; failures=$((failures + 1)); }

# run_ok <description> <command...>: the command must succeed
run_ok() {
    local desc="$1" out
    shift
    if out=$("$@" 2>&1); then pass "$desc"; else fail "$desc"; printf '%s\n' "$out" | sed 's/^/     /'; fi
}
# run_fails <description> <expected output (grep -E)> <command...>: the command must fail, saying so
run_fails() {
    local desc="$1" pattern="$2" out
    shift 2
    if out=$("$@" 2>&1); then
        fail "$desc: succeeded"
        printf '%s\n' "$out" | sed 's/^/     /'
    elif ! printf '%s\n' "$out" | grep -Eq -- "$pattern"; then
        fail "$desc: output does not match /$pattern/"
        printf '%s\n' "$out" | sed 's/^/     /'
    else
        pass "$desc"
    fi
}
# assert <description> <test expression...>
assert() {
    local desc="$1"
    shift
    if "$@"; then pass "$desc"; else fail "$desc"; fi
}

elf() { mkdir -p "$(dirname "$1")"; printf '\177ELF\002\001\001\000padding' > "$1"; }
macho() { mkdir -p "$(dirname "$1")"; printf '\317\372\355\376\007\000\000\001padding' > "$1"; }
sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'; else shasum -a 256 "$1" | awk '{print $1}'; fi; }

# lic <script> [args...]: runs <script> in a new bash with the helpers sourced and the args as $1, $2, ...
# Environment variables such as LIC_SYSROOT go in front: env VAR=value bash "$RUN" <script> [args...]
RUN="$WORK/run.sh"
{
    echo 'set -euo pipefail'
    printf 'source "%s"\n' "$ASSETS/collect-licenses.sh"
    echo 'script="$1"'
    echo 'shift'
    echo 'eval "$script"'
} > "$RUN"
lic() { bash "$RUN" "$@"; }

# -----------------------------------------------------------------------------
echo "--- lic_copy / lic_record / lic_write"
B="$WORK/basic"
mkdir -p "$WORK/src"
printf 'GPL text\n' > "$WORK/src/COPYING"
printf 'other text\n' > "$WORK/src/OTHER"
: > "$WORK/src/EMPTY"
BASIC='
    lic_init "$1" linux-x64 "linux/x64"
    lic_copy squashfs-tools "$2"
    lic_copy squashfs-tools "$2"                          # same file again: fine
    lic_record "linux/x64/mksquashfs" squashfs-tools
    lic_record "linux/x64/mksquashfs" squashfs-tools      # recorded once
    lic_record "linux/x64/mksquashfs" zstd-1.5.7
    lic_write squashfs-tools MODIFICATIONS "modified build"
    lic_source "- squashfs-tools 4.7.5"
    lic_source "- squashfs-tools 4.7.5"'
run_ok "lays out a component" lic "$BASIC" "$B" "$WORK/src/COPYING"
assert "license file copied" cmp -s "$WORK/src/COPYING" "$B/LICENSES/squashfs-tools/COPYING"
assert "manifest has each line once" [ "$(cat "$B/LICENSES/MANIFEST.tsv")" = "$(printf 'linux/x64/mksquashfs\tsquashfs-tools\nlinux/x64/mksquashfs\tzstd-1.5.7')" ]
assert "notice written" grep -qx "modified build" "$B/LICENSES/squashfs-tools/MODIFICATIONS"
assert "sources fragment has a heading and each line once" [ "$(cat "$B/LICENSES/SOURCES.d/linux-x64.md")" = "$(printf '## linux/x64\n\n- squashfs-tools 4.7.5')" ]
run_fails "rejects an empty license file" "missing or empty" lic 'lic_init "$1" x x && lic_copy c "$2"' "$B" "$WORK/src/EMPTY"
run_fails "rejects a missing license file" "missing or empty" lic 'lic_init "$1" x x && lic_copy c "$2"' "$B" "$WORK/src/NOPE"
run_fails "rejects different contents under the same name" "different contents" lic 'lic_init "$1" x x && lic_copy squashfs-tools "$2" COPYING' "$B" "$WORK/src/OTHER"
run_fails "rejects a component with a /" "invalid component" lic 'lic_init "$1" x x && lic_copy a/b "$2"' "$B" "$WORK/src/COPYING"
run_fails "rejects an absolute manifest path" "relative to the bundle" lic 'lic_init "$1" x x && lic_record /usr/bin/x c' "$B"
run_fails "rejects a ../ manifest path" "relative to the bundle" lic 'lic_init "$1" x x && lic_record lib/../../x c' "$B"
run_fails "requires lic_init" "lic_init was not called" lic 'lic_copy c "$1"' "$WORK/src/COPYING"

# -----------------------------------------------------------------------------
echo "--- lic_debian_lib (fake dpkg)"
SYSROOT="$WORK/sysroot"
FAKEBIN="$WORK/fakebin"
mkdir -p "$SYSROOT/usr/share/doc/liblzo2-2" "$SYSROOT/usr/share/common-licenses" "$SYSROOT/usr/lib/x86_64-linux-gnu" "$FAKEBIN"
printf 'Format: DEP-5\nLicense: GPL-2+\n On Debian systems, the full text of the GNU General Public License\n version 2 can be found in the file `/usr/share/common-licenses/GPL-2'"'"'.\n See also /usr/share/common-licenses/GPL-2.\n' \
    > "$SYSROOT/usr/share/doc/liblzo2-2/copyright"
printf 'GPL-2 full text\n' > "$SYSROOT/usr/share/common-licenses/GPL-2"
elf "$SYSROOT/usr/lib/x86_64-linux-gnu/liblzo2.so.2.0.0"
ln -s liblzo2.so.2.0.0 "$SYSROOT/usr/lib/x86_64-linux-gnu/liblzo2.so.2"
elf "$SYSROOT/usr/lib/x86_64-linux-gnu/libnobody.so.1"
mkdir -p "$SYSROOT/usr/share/doc/libxss1"
printf 'Copyright 1992 X Consortium\nPermission is hereby granted, free of charge\n' > "$SYSROOT/usr/share/doc/libxss1/copyright"
elf "$SYSROOT/usr/lib/x86_64-linux-gnu/libXss.so.1.0.0"
cat > "$FAKEBIN/dpkg" <<EOF
#!/usr/bin/env bash
[ "\$1" = "-S" ] || exit 2
case "\$2" in
    */liblzo2.so.2|*/liblzo2.so.2.0.0) echo "liblzo2-2:amd64: \$2" ;;
    */libXss.so.1.0.0) echo "libxss1:amd64: \$2" ;;
    *) echo "dpkg-query: no path found matching pattern \$2" >&2; exit 1 ;;
esac
EOF
cat > "$FAKEBIN/dpkg-query" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "-W" ] || exit 1
case "$3" in
    liblzo2-2:amd64) printf '2.08-1.2\tlzo2\t2.08-1.2' ;;
    libxss1:amd64) printf '1:1.2.2-1\tlibxss\t1:1.2.2-1' ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$FAKEBIN/dpkg" "$FAKEBIN/dpkg-query"
D="$WORK/debian"
DEBIAN_CASE='lic_init "$1" linux-x64 "linux/x64" && lic_debian_lib "$2" && printf "%s\n" "$LIC_COMPONENT" > "$1/component"'
run_ok "finds the package of a library (through its symlink)" env PATH="$FAKEBIN:$PATH" LIC_SYSROOT="$SYSROOT" \
    bash "$RUN" "$DEBIAN_CASE" "$D" "$SYSROOT/usr/lib/x86_64-linux-gnu/liblzo2.so.2"
assert "component is debian-<package>" [ "$(cat "$D/component" 2>/dev/null)" = "debian-liblzo2-2" ]
assert "copyright copied" cmp -s "$SYSROOT/usr/share/doc/liblzo2-2/copyright" "$D/LICENSES/debian-liblzo2-2/copyright"
assert "common license it refers to copied (GPL-2, not GPL-2.)" cmp -s "$SYSROOT/usr/share/common-licenses/GPL-2" "$D/LICENSES/debian-liblzo2-2/GPL-2"
assert "only the referenced files" [ "$(cd "$D/LICENSES/debian-liblzo2-2" && echo *)" = "GPL-2 copyright" ]
assert "source package recorded" grep -q '`liblzo2-2` 2.08-1.2 (Ubuntu 18.04 package; source package `lzo2` 2.08-1.2: https://launchpad.net/ubuntu/+source/lzo2/2.08-1.2)' "$D/LICENSES/SOURCES.d/linux-x64.md"
run_ok "a copyright that refers to no common license" env PATH="$FAKEBIN:$PATH" LIC_SYSROOT="$SYSROOT" \
    bash "$RUN" "$DEBIAN_CASE" "$WORK/debian-xss" "$SYSROOT/usr/lib/x86_64-linux-gnu/libXss.so.1.0.0"
assert "only its copyright" test "$(cd "$WORK/debian-xss/LICENSES/debian-libxss1" && echo *)" = "copyright"
run_fails "fails for a library no package owns" "not owned by any installed package" env PATH="$FAKEBIN:$PATH" LIC_SYSROOT="$SYSROOT" \
    bash "$RUN" 'lic_init "$1" x x && lic_debian_lib "$2"' "$WORK/debian-2" "$SYSROOT/usr/lib/x86_64-linux-gnu/libnobody.so.1"
mv "$SYSROOT/usr/share/common-licenses/GPL-2" "$WORK/GPL-2.moved"
run_fails "fails when a referenced common license is missing" "license file missing or empty: .*/common-licenses/GPL-2$" env PATH="$FAKEBIN:$PATH" LIC_SYSROOT="$SYSROOT" \
    bash "$RUN" 'lic_init "$1" x x && lic_debian_lib "$2"' "$WORK/debian-3" "$SYSROOT/usr/lib/x86_64-linux-gnu/liblzo2.so.2"
mv "$WORK/GPL-2.moved" "$SYSROOT/usr/share/common-licenses/GPL-2"

echo "--- lic_debian_lib (extracted .deb, as for the i386 libappindicator)"
DEB="$WORK/appind"
mkdir -p "$DEB/usr/lib/i386-linux-gnu" "$DEB/usr/share/doc/libappindicator1" "$DEB/DEBIAN"
elf "$DEB/usr/lib/i386-linux-gnu/libappindicator.so.1.0.0"
printf 'License: GPL-3\n /usr/share/common-licenses/GPL-3\n' > "$DEB/usr/share/doc/libappindicator1/copyright"
printf 'GPL-3 full text\n' > "$SYSROOT/usr/share/common-licenses/GPL-3"
printf 'Package: libappindicator1\nSource: libappindicator\nVersion: 12.10.1+18.04.20180322.1-0ubuntu1\nArchitecture: i386\n' > "$DEB/DEBIAN/control"
D="$WORK/deb"
run_ok "uses the extracted package's control file and copyright" env PATH="$FAKEBIN:$PATH" LIC_SYSROOT="$SYSROOT" LIC_DEB_ROOTS="/nonexistent $DEB" \
    bash "$RUN" "$DEBIAN_CASE" "$D" "$DEB/usr/lib/i386-linux-gnu/libappindicator.so.1.0.0"
assert "component is debian-libappindicator1" [ "$(cat "$D/component" 2>/dev/null)" = "debian-libappindicator1" ]
assert "GPL-3 copied" cmp -s "$SYSROOT/usr/share/common-licenses/GPL-3" "$D/LICENSES/debian-libappindicator1/GPL-3"
assert "source package from Source:" grep -q 'source package `libappindicator` 12.10.1+18.04.20180322.1-0ubuntu1' "$D/LICENSES/SOURCES.d/linux-x64.md"
rm "$DEB/DEBIAN/control"
run_fails "fails without the extracted control file" "dpkg-deb -e" env LIC_SYSROOT="$SYSROOT" LIC_DEB_ROOTS="$DEB" \
    bash "$RUN" 'lic_init "$1" x x && lic_debian_lib "$2"' "$WORK/deb-2" "$DEB/usr/lib/i386-linux-gnu/libappindicator.so.1.0.0"

# -----------------------------------------------------------------------------
echo "--- lic_homebrew_lib (fake Homebrew prefix)"
BREW="$WORK/homebrew"
KEG="$BREW/Cellar/libpng/1.6.58"
mkdir -p "$KEG/lib" "$KEG/.brew" "$BREW/opt" "$BREW/Cellar/nolicense/1.0/lib"
macho "$KEG/lib/libpng16.16.dylib"
printf 'PNG Reference Library License version 2\n' > "$KEG/LICENSE"
printf 'notice\n' > "$KEG/NOTICE.md"
printf 'readme\n' > "$KEG/README.md"
printf 'class Libpng < Formula\n  url "https://downloads.sourceforge.net/project/libpng/libpng16/1.6.58/libpng-1.6.58.tar.xz"\n  license "libpng-2.0"\nend\n' > "$KEG/.brew/libpng.rb"
ln -s ../Cellar/libpng/1.6.58 "$BREW/opt/libpng"
macho "$BREW/Cellar/nolicense/1.0/lib/libx.dylib"
macho "$WORK/usr-local/lib/libloose.dylib"
H="$WORK/brew-bundle"
run_ok "finds the keg of a dylib (through opt/)" env LIC_OS=darwin \
    bash "$RUN" 'lic_init "$1" darwin-arm64 "darwin/arm64" && lic_system_lib "$2" && printf "%s\n" "$LIC_COMPONENT" > "$1/component"' "$H" "$BREW/opt/libpng/lib/libpng16.16.dylib"
assert "component is homebrew-<formula>-<version>" [ "$(cat "$H/component" 2>/dev/null)" = "homebrew-libpng-1.6.58" ]
assert "LICENSE and NOTICE copied, README not" [ "$(cd "$H/LICENSES/homebrew-libpng-1.6.58" && echo *)" = "LICENSE NOTICE.md" ]
assert "formula source and license recorded" grep -q 'Homebrew `libpng` 1.6.58 (formula license: "libpng-2.0"): https://downloads.sourceforge.net/project/libpng/libpng16/1.6.58/libpng-1.6.58.tar.xz' "$H/LICENSES/SOURCES.d/darwin-arm64.md"
run_fails "fails for a keg without license files" "has no LICENSE/COPYING/NOTICE" lic 'lic_init "$1" x x && lic_homebrew_lib "$2"' "$WORK/brew-2" "$BREW/Cellar/nolicense/1.0/lib/libx.dylib"
run_fails "fails for a dylib outside a keg" "not in a Homebrew keg" lic 'lic_init "$1" x x && lic_homebrew_lib "$2"' "$WORK/brew-3" "$WORK/usr-local/lib/libloose.dylib"

# -----------------------------------------------------------------------------
echo "--- lic_fetch / lic_fetch_pins (file:// URLs)"
printf 'MIT license text\n' > "$WORK/src/LICENSE.runtime"
printf 'musl COPYRIGHT\n' > "$WORK/src/COPYRIGHT"
RT_SHA=$(sha256 "$WORK/src/LICENSE.runtime")
MUSL_SHA=$(sha256 "$WORK/src/COPYRIGHT")
mkdir -p "$WORK/srv/20251108"
cp "$WORK/src/LICENSE.runtime" "$WORK/srv/20251108/LICENSE"
F="$WORK/fetch"
run_ok "fetches a pinned file" lic 'lic_init "$1" x x && lic_fetch type2-runtime LICENSE "$2" "file://$3"' "$F" "$RT_SHA" "$WORK/src/LICENSE.runtime"
assert "fetched file in place" cmp -s "$WORK/src/LICENSE.runtime" "$F/LICENSES/type2-runtime/LICENSE"
run_fails "rejects a SHA256 mismatch" "no URL served the pinned file" lic 'lic_init "$1" x x && lic_fetch musl COPYRIGHT "$2" "file://$3"' "$WORK/fetch-2" "$MUSL_SHA" "$WORK/src/LICENSE.runtime"
run_ok "falls back to the next URL" lic 'lic_init "$1" x x && lic_fetch musl COPYRIGHT "$2" "file://$3/missing" "file://$3/LICENSE.runtime" "file://$3/COPYRIGHT"' "$WORK/fetch-3" "$MUSL_SHA" "$WORK/src"
assert "fallback file in place" cmp -s "$WORK/src/COPYRIGHT" "$WORK/fetch-3/LICENSES/musl/COPYRIGHT"

PINS="$WORK/pins.tsv"
printf '# header\n# type2-runtime-release: 20251108\n# source: - type2-runtime {APPIMAGE_TYPE2_RELEASE}\n\ntype2-runtime\tLICENSE\t%s\tfile://%s/srv/{APPIMAGE_TYPE2_RELEASE}/LICENSE\r\nmusl\tCOPYRIGHT\t%s\tfile://%s/missing?h=v1.2.5 file://%s/src/COPYRIGHT\n' \
    "$RT_SHA" "$WORK" "$MUSL_SHA" "$WORK" "$WORK" > "$PINS"
run_ok "fetches every pin (CRLF, release placeholder, fallback URL with ?)" lic 'lic_init "$1" runtimes runtimes && lic_fetch_pins "$2" 20251108' "$WORK/pins" "$PINS"
assert "both pinned files fetched" test -s "$WORK/pins/LICENSES/type2-runtime/LICENSE" -a -s "$WORK/pins/LICENSES/musl/COPYRIGHT"
assert "source line added with the release" grep -qx -- "- type2-runtime 20251108" "$WORK/pins/LICENSES/SOURCES.d/runtimes.md"
assert "components listed once each" [ "$(lic 'lic_pins_components "$1"' "$PINS" | tr '\n' ' ')" = "type2-runtime musl " ]
run_fails "refuses pins made for another runtime release" "pinned for type2-runtime '20251108', building '20260101'" lic 'lic_init "$1" x x && lic_fetch_pins "$2" 20260101' "$WORK/pins-2" "$PINS"
printf '# type2-runtime-release: 20251108\nmusl\tCOPYRIGHT\n' > "$WORK/pins-bad.tsv"
run_fails "rejects a malformed pin" "malformed line" lic 'lic_init "$1" x x && lic_fetch_pins "$2" 20251108' "$WORK/pins-3" "$WORK/pins-bad.tsv"

echo "--- the real runtime pins file"
REAL_PINS="$ASSETS/runtime-licenses.tsv"
assert "declares the release build.sh downloads" grep -qx "# type2-runtime-release: $(sed -n 's/^export APPIMAGE_TYPE2_RELEASE="\(.*\)"$/\1/p' "$ASSETS/../build.sh")" "$REAL_PINS"
assert "every pin line has 4 columns, a 64-hex SHA256 and https URLs" \
    awk -F'\t' '/^[^#]/ && NF { if (NF != 4 || $3 !~ /^[0-9a-f]{64}$/ || $4 !~ /^https:\/\//) bad = 1 } END { exit bad }' "$REAL_PINS"
assert "no URL on a branch (master/main/dev/HEAD)" bash -c '! grep -E "/(master|main|dev|HEAD)/" "$1"' _ "$REAL_PINS"

# -----------------------------------------------------------------------------
echo "--- lic_merge / lic_finalize_sources and the guard"
# Two platform bundles laid out like build-appimage.sh output, sharing the squashfs-tools license
mkbundle() {
    local b="$1" plat="$2"
    elf "$b/linux/$plat/mksquashfs"
    elf "$b/linux/$plat/lib/liblzo2.so.2.0.0"
    ln -s liblzo2.so.2.0.0 "$b/linux/$plat/lib/liblzo2.so.2"
    lic '
        lic_init "$1" "linux-$2" "linux/$2"
        lic_copy squashfs-tools "$3"
        lic_copy debian-liblzo2-2 "$4" copyright
        lic_record "linux/$2/mksquashfs" squashfs-tools
        lic_record "linux/$2/lib/liblzo2.so.2.0.0" debian-liblzo2-2
        lic_source "- built for $2"' "$b" "$plat" "$WORK/src/COPYING" "$SYSROOT/usr/share/doc/liblzo2-2/copyright"
}
mkbundles() { mkbundle "$WORK/m-x64" x64 && mkbundle "$WORK/m-arm64" arm64; }
run_ok "lays out two platform bundles" mkbundles
run_ok "guard accepts a platform bundle" bash "$VERIFY" "$WORK/m-x64"
M="$WORK/merged"
run_ok "merges both" lic 'lic_merge "$1" "$2" && lic_merge "$1" "$3"' "$M" "$WORK/m-x64" "$WORK/m-arm64"
assert "manifest is the union" [ "$(wc -l < "$M/LICENSES/MANIFEST.tsv" | tr -d ' ')" = 4 ]
assert "symlink kept as a symlink" [ -L "$M/linux/arm64/lib/liblzo2.so.2" ]
assert "both sources fragments kept" test -f "$M/LICENSES/SOURCES.d/linux-x64.md" -a -f "$M/LICENSES/SOURCES.d/linux-arm64.md"
run_ok "merging the same bundle again is a no-op" lic 'lic_merge "$1" "$2"' "$M" "$WORK/m-x64"
assert "manifest unchanged" [ "$(wc -l < "$M/LICENSES/MANIFEST.tsv" | tr -d ' ')" = 4 ]
run_ok "guard accepts the merged bundle" bash "$VERIFY" "$M"
printf '%s\n' "# Sources" > "$WORK/header.md"
run_ok "folds the sources fragments into SOURCES.md" lic 'lic_finalize_sources "$1" "$2"' "$M" "$WORK/header.md"
assert "SOURCES.md has the header and both fragments, SOURCES.d is gone" \
    bash -c 'grep -qx "# Sources" "$1" && grep -qx -- "- built for x64" "$1" && grep -qx -- "- built for arm64" "$1" && [ ! -e "${1%/*}/SOURCES.d" ]' _ "$M/LICENSES/SOURCES.md"
run_ok "guard still accepts it" bash "$VERIFY" "$M"

cp -R "$WORK/m-arm64" "$WORK/m-conflict"
printf 'a different GPL text\n' > "$WORK/m-conflict/LICENSES/squashfs-tools/COPYING"
run_fails "refuses to merge a different license file under the same name" "merge conflict: LICENSES/squashfs-tools/COPYING differs" lic 'lic_merge "$1" "$2"' "$M" "$WORK/m-conflict"
rm -rf "$WORK/m-conflict"
cp -R "$WORK/m-arm64" "$WORK/m-conflict"
rm "$WORK/m-conflict/linux/arm64/lib/liblzo2.so.2"
ln -s elsewhere.so "$WORK/m-conflict/linux/arm64/lib/liblzo2.so.2"
run_fails "refuses to merge a symlink with another target" "links to different targets" lic 'lic_merge "$1" "$2"' "$M" "$WORK/m-conflict"

# A binary the build forgot to record makes the guard fail, naming it
elf "$M/linux/x64/unrecorded-tool"
run_fails "guard rejects an unrecorded binary" "linux/x64/unrecorded-tool: elf binary not listed" bash "$VERIFY" "$M"
rm "$M/linux/x64/unrecorded-tool"
rm -rf "$M/LICENSES/debian-liblzo2-2"
run_fails "guard rejects a component without license files" "LICENSES/debian-liblzo2-2/: missing" bash "$VERIFY" "$M"

echo ""
if [ "$failures" -ne 0 ]; then
    echo "❌ $failures test(s) failed"
    exit 1
fi
echo "✓ All collect-licenses tests passed"
