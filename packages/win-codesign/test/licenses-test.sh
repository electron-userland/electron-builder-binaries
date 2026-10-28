#!/usr/bin/env bash
# Unit tests for assets/licenses.sh (the LICENSES/ layout every win-codesign bundle ships) and
# assets/verify-bundle-licenses.sh (the shared guard, scripts/verify-licenses.sh, on a bundle zip or directory).
# Binaries are stand-ins: a few bytes with the right magic number, never executed.
# Run: bash packages/win-codesign/test/licenses-test.sh
set -uo pipefail

PASS=0
FAIL=0
ASSETS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../assets" && pwd)"

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        echo "  ✅ $desc"
        PASS=$(( PASS + 1 ))
    else
        echo "  ❌ $desc"
        echo "     expected: $(printf '%q' "$expected")"
        echo "     actual:   $(printf '%q' "$actual")"
        FAIL=$(( FAIL + 1 ))
    fi
}

# assert_exit <desc> <expected exit code> <command...>: output goes to $OUT
OUT=""
assert_exit() {
    local desc="$1" expected_code="$2" actual_code=0
    shift 2
    OUT=$("$@" 2>&1) || actual_code=$?
    assert_eq "$desc" "$expected_code" "$actual_code"
    if [ "$actual_code" != "$expected_code" ]; then
        printf '%s\n' "$OUT" | sed 's/^/       /'
    fi
}

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# shellcheck source=../assets/licenses.sh
source "$ASSETS_DIR/licenses.sh"

elf()   { mkdir -p "$(dirname "$1")"; printf '\177ELF\002\001\001\000' > "$1"; }
macho() { mkdir -p "$(dirname "$1")"; printf '\317\372\355\376\014\000\000\001' > "$1"; }
pe()    { mkdir -p "$(dirname "$1")"; printf 'MZ\220\000mock' > "$1"; }
text()  { mkdir -p "$(dirname "$1")"; printf '%s\n' "${2:-text}" > "$1"; }
manifest() { grep -v '^#' "$1/MANIFEST.tsv"; }

# ── license_add / license_add_dir ─────────────────────────────────────────────
echo ""
echo "▶ license_add / license_add_dir"

SRC="$TMPDIR_ROOT/src"
text "$SRC/LICENSE" "MIT License"
text "$SRC/COPYING" "GPL"
: > "$SRC/EMPTY"
mkdir -p "$SRC/empty-dir"

L="$TMPDIR_ROOT/add/LICENSES"
assert_exit "copies the license files" 0 license_add "$L" comp "$SRC/LICENSE" "$SRC/COPYING"
assert_eq "LICENSES/comp/LICENSE" "MIT License" "$(cat "$L/comp/LICENSE" 2>/dev/null)"
assert_eq "LICENSES/comp/COPYING" "GPL" "$(cat "$L/comp/COPYING" 2>/dev/null)"
assert_eq "creates MANIFEST.tsv with only a comment" "" "$(manifest "$L")"
assert_exit "fails on a missing license file" 1 license_add "$L" comp2 "$SRC/NOPE"
assert_eq "  and names it" "1" "$(echo "$OUT" | grep -c 'missing or empty: .*NOPE')"
assert_exit "fails on an empty license file" 1 license_add "$L" comp3 "$SRC/EMPTY"
assert_exit "fails without license files" 1 license_add "$L" comp4
for bad in "" "." ".." "a/b" 'a\b'; do
    assert_exit "rejects component name '$bad'" 1 license_add "$L" "$bad" "$SRC/LICENSE"
done
assert_exit "license_add_dir fails when a file in the directory is empty" 1 license_add_dir "$L" dircomp "$SRC"
rm -f "$SRC/EMPTY"
assert_exit "license_add_dir copies every file of a directory" 0 license_add_dir "$L" dircomp2 "$SRC"
assert_eq "  LICENSE and COPYING copied" "COPYING LICENSE" "$(cd "$L/dircomp2" && printf '%s ' * | sed 's/ $//')"
assert_exit "license_add_dir fails on a missing directory" 1 license_add_dir "$L" x "$SRC/nope"
assert_exit "license_add_dir fails on a directory without files" 1 license_add_dir "$L" x "$SRC/empty-dir"

# ── license_map / license_exempt / license_source ─────────────────────────────
echo ""
echo "▶ license_map / license_exempt / license_source"

L="$TMPDIR_ROOT/map/LICENSES"
license_map "$L" comp bin/a 'lib/*.so'
license_map "$L" other bin/a
assert_eq "MANIFEST.tsv lines" "bin/a	comp
lib/*.so	comp
bin/a	other" "$(manifest "$L")"
assert_exit "license_map rejects an invalid component" 1 license_map "$L" "a/b" bin/a
license_exempt "$L" "pending" '*/x.exe' y.dll
assert_eq "EXEMPT.tsv lines" "*/x.exe	pending
y.dll	pending" "$(grep -v '^#' "$L/EXEMPT.tsv")"
assert_exit "license_exempt requires a reason" 1 license_exempt "$L" "" z.dll
license_source "$L" comp 1.0 https://example.invalid/comp
license_source "$L" comp 2.0 https://example.invalid/again
license_source "$L" other 3.0 "MSYS2 package other"
assert_eq "SOURCES.tsv: one line per component" "comp	1.0	https://example.invalid/comp
other	3.0	MSYS2 package other" "$(grep -v '^#' "$L/SOURCES.tsv")"

# ── license_verify / verify-bundle-licenses.sh ────────────────────────────────
echo ""
echo "▶ license_verify / verify-bundle-licenses.sh"

B="$TMPDIR_ROOT/verify/bundle"
elf "$B/bin/tool"
text "$B/README" "not a binary"
license_add "$B/LICENSES" tool "$SRC/LICENSE"
license_map "$B/LICENSES" tool bin/tool
(cd "$B" && zip -q -r "$TMPDIR_ROOT/verify/good.zip" .)
assert_exit "passes on a directory" 0 bash "$ASSETS_DIR/verify-bundle-licenses.sh" "$B"
assert_exit "passes on a zip" 0 bash "$ASSETS_DIR/verify-bundle-licenses.sh" "$TMPDIR_ROOT/verify/good.zip"
elf "$B/bin/unlisted"
(cd "$B" && zip -q -r "$TMPDIR_ROOT/verify/bad.zip" .)
assert_exit "fails on a directory with an unlisted binary" 1 bash "$ASSETS_DIR/verify-bundle-licenses.sh" "$B"
assert_eq "  and names it" "1" "$(echo "$OUT" | grep -c 'bin/unlisted: elf binary not listed')"
assert_exit "fails on a zip with an unlisted binary" 1 bash "$ASSETS_DIR/verify-bundle-licenses.sh" "$TMPDIR_ROOT/verify/bad.zip"
assert_exit "fails when any of several bundles fails" 1 \
    bash "$ASSETS_DIR/verify-bundle-licenses.sh" "$TMPDIR_ROOT/verify/good.zip" "$TMPDIR_ROOT/verify/bad.zip"
assert_exit "exits 2 without arguments" 2 bash "$ASSETS_DIR/verify-bundle-licenses.sh"
assert_exit "exits 2 on a missing path" 2 bash "$ASSETS_DIR/verify-bundle-licenses.sh" "$TMPDIR_ROOT/nope.zip"
text "$TMPDIR_ROOT/verify/not-a.zip" "garbage"
assert_exit "exits 2 on a file that is not a zip" 2 bash "$ASSETS_DIR/verify-bundle-licenses.sh" "$TMPDIR_ROOT/verify/not-a.zip"
assert_exit "exits 2 when the guard is missing" 2 \
    env VERIFY_LICENSES_SH="$TMPDIR_ROOT/no-guard.sh" bash "$ASSETS_DIR/verify-bundle-licenses.sh" "$B"

# ── osslsigncode_unix_licenses (macOS / Linux bundles) ────────────────────────
echo ""
echo "▶ osslsigncode_unix_licenses"

# Stand-in source trees, laid out as the osslsigncode clone and the OpenSSL / libp11 tarballs are
OSS="$TMPDIR_ROOT/unix/src"
text "$OSS/osslsigncode/LICENSE.txt" "osslsigncode license"
text "$OSS/osslsigncode/COPYING.txt" "GNU GENERAL PUBLIC LICENSE Version 3"
text "$OSS/openssl/LICENSE.txt" "Apache License 2.0"
text "$OSS/libp11/COPYING" "GNU LESSER GENERAL PUBLIC LICENSE"
OSSLSIGNCODE_VER=2.14 OPENSSL_VER=3.5.9 LIBP11_VER=0.4.21

for variant in linux darwin; do
    U="$TMPDIR_ROOT/unix/$variant"
    if [ "$variant" = linux ]; then
        elf "$U/bin/osslsigncode"; elf "$U/lib/libcrypto.so.3"; elf "$U/lib/libssl.so.3"
        elf "$U/lib/ossl-modules/pkcs11prov.so"
    else
        macho "$U/bin/osslsigncode"; macho "$U/lib/libcrypto.3.dylib"; macho "$U/lib/libssl.3.dylib"
        macho "$U/lib/ossl-modules/pkcs11prov.dylib"
    fi
    text "$U/osslsigncode" "#!/usr/bin/env bash"
    text "$U/VERSION.txt"
    assert_exit "$variant: lays out LICENSES/" 0 \
        osslsigncode_unix_licenses "$U/LICENSES" "$OSS/osslsigncode" "$OSS/openssl" "$OSS/libp11"
    assert_exit "$variant: the guard passes" 0 bash "$ASSETS_DIR/verify-bundle-licenses.sh" "$U"
    assert_eq "$variant: 4 binaries checked" "1" "$(echo "$OUT" | grep -c '✓ All 4 binaries have license files (0 exempted')"
done
assert_eq "ships osslsigncode's LICENSE.txt and COPYING.txt" "COPYING.txt LICENSE.txt" \
    "$(cd "$U/LICENSES/osslsigncode" && printf '%s ' * | sed 's/ $//')"
assert_eq "SOURCES.tsv names the pinned versions" "osslsigncode	2.14	https://github.com/mtrojnar/osslsigncode/tree/2.14
openssl	3.5.9	https://github.com/openssl/openssl/releases/download/openssl-3.5.9/openssl-3.5.9.tar.gz
libp11	0.4.21	https://github.com/OpenSC/libp11/releases/download/libp11-0.4.21/libp11-0.4.21.tar.gz" \
    "$(grep -v '^#' "$U/LICENSES/SOURCES.tsv")"
rm -f "$OSS/osslsigncode/COPYING.txt"
assert_exit "fails without osslsigncode's COPYING.txt (full GPLv3 text)" 1 \
    osslsigncode_unix_licenses "$TMPDIR_ROOT/unix/nocopying/LICENSES" "$OSS/osslsigncode" "$OSS/openssl" "$OSS/libp11"
# A bundle with a library nobody mapped fails the guard
elf "$TMPDIR_ROOT/unix/linux/lib/libextra.so.1"
assert_exit "the guard fails on an extra, unmapped library" 1 \
    bash "$ASSETS_DIR/verify-bundle-licenses.sh" "$TMPDIR_ROOT/unix/linux"
assert_eq "  and names it" "1" "$(echo "$OUT" | grep -c 'lib/libextra.so.1: elf binary not listed')"

# ── osslsigncode_windows_licenses / msys2_dll_license (Windows bundles) ───────
echo ""
echo "▶ osslsigncode_windows_licenses (fake pacman)"

W="$TMPDIR_ROOT/win"
PREFIX="$W/mingw64"
FAKE_BIN="$W/fake-bin"
text "$W/src/osslsigncode/LICENSE.txt" "osslsigncode license"
text "$W/src/osslsigncode/COPYING.txt" "GNU GENERAL PUBLIC LICENSE Version 3"
# What the MSYS2 packages install (mingw-w64-openssl / mingw-w64-zlib PKGBUILDs: share/licenses/<name>/LICENSE)
text "$PREFIX/share/licenses/openssl/LICENSE" "Apache License 2.0"
text "$PREFIX/share/licenses/zlib/LICENSE" "zlib license"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/pacman" << 'FAKE_PACMAN'
#!/usr/bin/env bash
# pacman -Qqo <file> | pacman -Q <pkg>
case "$1" in
    -Qqo)
        case "${2##*/}" in
            libcrypto-3-x64.dll|libssl-3-x64.dll) echo "mingw-w64-x86_64-openssl" ;;
            zlib1.dll) echo "mingw-w64-x86_64-zlib" ;;
            libnolicense.dll) echo "mingw-w64-x86_64-nolicense" ;;
            *) echo "error: No package owns $2" >&2; exit 1 ;;
        esac ;;
    -Q)
        case "$2" in
            mingw-w64-x86_64-openssl) echo "$2 3.6.5-1" ;;
            *) echo "$2 1.0-1" ;;
        esac ;;
    *) exit 2 ;;
esac
FAKE_PACMAN
chmod +x "$FAKE_BIN/pacman"

win_bundle() {
    rm -rf "$W/bundle"
    pe "$W/bundle/bin/osslsigncode.exe"
    local dll
    for dll in "$@"; do pe "$W/bundle/bin/$dll"; done
    text "$W/bundle/osslsigncode.bat" "@echo off"
}

win_bundle libcrypto-3-x64.dll libssl-3-x64.dll zlib1.dll
# shellcheck disable=SC2016 # expanded by the inner bash
assert_exit "lays out LICENSES/ for osslsigncode.exe and its DLLs" 0 \
    env PATH="$FAKE_BIN:$PATH" bash -c 'source "$1/licenses.sh"; OSSLSIGNCODE_VER=2.14 osslsigncode_windows_licenses "$2" "$3" mingw-w64-x86_64 "$4"' \
    _ "$ASSETS_DIR" "$W/bundle" "$W/src/osslsigncode" "$PREFIX"
assert_eq "MANIFEST.tsv: osslsigncode.exe (with OpenSSL's applink.c) and each DLL's package" "bin/osslsigncode.exe	osslsigncode
bin/osslsigncode.exe	openssl
bin/libcrypto-3-x64.dll	openssl
bin/libssl-3-x64.dll	openssl
bin/zlib1.dll	zlib" "$(manifest "$W/bundle/LICENSES")"
assert_eq "ships osslsigncode's LICENSE.txt and COPYING.txt" "COPYING.txt LICENSE.txt" \
    "$(cd "$W/bundle/LICENSES/osslsigncode" && printf '%s ' * | sed 's/ $//')"
assert_eq "ships MSYS2's OpenSSL license" "Apache License 2.0" "$(cat "$W/bundle/LICENSES/openssl/LICENSE" 2>/dev/null)"
assert_eq "ships MSYS2's zlib license" "zlib license" "$(cat "$W/bundle/LICENSES/zlib/LICENSE" 2>/dev/null)"
assert_eq "SOURCES.tsv records the MSYS2 package versions" "osslsigncode	2.14	https://github.com/mtrojnar/osslsigncode/tree/2.14
openssl	3.6.5-1	MSYS2 package mingw-w64-x86_64-openssl (https://packages.msys2.org/)
zlib	1.0-1	MSYS2 package mingw-w64-x86_64-zlib (https://packages.msys2.org/)" \
    "$(grep -v '^#' "$W/bundle/LICENSES/SOURCES.tsv")"
assert_exit "the guard passes" 0 bash "$ASSETS_DIR/verify-bundle-licenses.sh" "$W/bundle"

win_bundle libcrypto-3-x64.dll libunowned.dll
# shellcheck disable=SC2016 # expanded by the inner bash
assert_exit "fails on a DLL no MSYS2 package owns" 1 \
    env PATH="$FAKE_BIN:$PATH" bash -c 'source "$1/licenses.sh"; OSSLSIGNCODE_VER=2.14 osslsigncode_windows_licenses "$2" "$3" mingw-w64-x86_64 "$4"' \
    _ "$ASSETS_DIR" "$W/bundle" "$W/src/osslsigncode" "$PREFIX"
assert_eq "  and names it" "1" "$(echo "$OUT" | grep -c 'No MSYS2 package owns .*libunowned.dll')"

win_bundle libnolicense.dll
# shellcheck disable=SC2016 # expanded by the inner bash
assert_exit "fails on a DLL whose package installs no license files" 1 \
    env PATH="$FAKE_BIN:$PATH" bash -c 'source "$1/licenses.sh"; OSSLSIGNCODE_VER=2.14 osslsigncode_windows_licenses "$2" "$3" mingw-w64-x86_64 "$4"' \
    _ "$ASSETS_DIR" "$W/bundle" "$W/src/osslsigncode" "$PREFIX"
assert_eq "  and names the missing directory" "1" "$(echo "$OUT" | grep -c 'License directory for nolicense not found: .*share/licenses/nolicense')"

win_bundle zlib1.dll
rm -f "$W/src/osslsigncode/COPYING.txt"
# shellcheck disable=SC2016 # expanded by the inner bash
assert_exit "fails without osslsigncode's COPYING.txt" 1 \
    env PATH="$FAKE_BIN:$PATH" bash -c 'source "$1/licenses.sh"; OSSLSIGNCODE_VER=2.14 osslsigncode_windows_licenses "$2" "$3" mingw-w64-x86_64 "$4"' \
    _ "$ASSETS_DIR" "$W/bundle" "$W/src/osslsigncode" "$PREFIX"

echo ""
echo "═══════════════════════════════════════"
echo "Results: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════"
[ "$FAIL" -eq 0 ]
