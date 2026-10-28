#!/usr/bin/env bash
# Self-test for collect-licenses.sh and verify-bundle-licenses.sh on a stand-in bundle (files with Mach-O magic bytes)
# and stand-in source tarballs, so it runs anywhere (macOS, Linux) without Homebrew. Called by test.sh; also:
#   bash packages/linux-tools-mac/assets/test-licenses.sh
# The fixture "license" files are placeholders: real texts only ever come from the upstream tarballs at build time.
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECT="$SCRIPT_DIR/collect-licenses.sh"
VERIFY="$SCRIPT_DIR/verify-bundle-licenses.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/linux-tools-mac-license-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
ok() { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; fail=$((fail + 1)); }

sha256_of() {
    if command -v sha256sum > /dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'; else shasum -a 256 "$1" | awk '{print $1}'; fi
}

CELLAR=/opt/homebrew/Cellar

# ── fixtures ──
# make_tarball <top dir> <file>...: <WORK>/src/<top dir>.tar.gz holding placeholder files
make_tarball() {
    local top="$1" f
    shift
    rm -rf "$WORK/srctree"
    mkdir -p "$WORK/srctree/$top" "$WORK/src"
    for f in "$@"; do
        mkdir -p "$(dirname "$WORK/srctree/$top/$f")"
        printf 'placeholder %s for %s (test fixture)\n' "$f" "$top" > "$WORK/srctree/$top/$f"
    done
    tar -czf "$WORK/src/$top.tar.gz" -C "$WORK/srctree" "$top"
}

make_sources() {
    make_tarball tar-1.35 COPYING AUTHORS README
    make_tarball lzip-1.26 COPYING AUTHORS
    make_tarball binutils-2.47 COPYING COPYING.LIB COPYING3 COPYING3.LIB binutils/COPYING
    make_tarball zstd-1.5.7 LICENSE COPYING lib/dictBuilder/divsufsort.c
    # divsufsort.c starts with its MIT comment block
    mkdir -p "$WORK/srctree/zstd-1.5.7/lib/dictBuilder"
    printf '/*\n * divsufsort.c (fixture)\n * Copyright (c) fixture\n */\n\nint x;\n' \
        > "$WORK/srctree/zstd-1.5.7/lib/dictBuilder/divsufsort.c"
    printf 'placeholder LICENSE\n' > "$WORK/srctree/zstd-1.5.7/LICENSE"
    printf 'placeholder COPYING\n' > "$WORK/srctree/zstd-1.5.7/COPYING"
    tar -czf "$WORK/src/zstd-1.5.7.tar.gz" -C "$WORK/srctree" zstd-1.5.7
}

write_sources_tsv() {
    local s="$WORK/src"
    {
        printf '# fixture\n'
        printf 'gnu-tar\t1.35\thttps://example.invalid/tar-1.35.tar.gz\t%s\t%s\tGPL-3.0-or-later\thttps://example.invalid/gnu-tar.rb\n' \
            "$(sha256_of "$s/tar-1.35.tar.gz")" "$s/tar-1.35.tar.gz"
        printf 'lzip\t1.26\thttps://example.invalid/lzip-1.26.tar.gz\t%s\t%s\t\thttps://example.invalid/lzip.rb\n' \
            "$(sha256_of "$s/lzip-1.26.tar.gz")" "$s/lzip-1.26.tar.gz"
        printf 'binutils\t2.47\thttps://example.invalid/binutils-2.47.tar.gz\t%s\t%s\tGPL-3.0-or-later\thttps://example.invalid/binutils.rb\n' \
            "$(sha256_of "$s/binutils-2.47.tar.gz")" "$s/binutils-2.47.tar.gz"
        printf 'zstd\t1.5.7\thttps://example.invalid/zstd-1.5.7.tar.gz\t%s\t%s\tBSD-3-Clause OR GPL-2.0-only\thttps://example.invalid/zstd.rb\n' \
            "$(sha256_of "$s/zstd-1.5.7.tar.gz")" "$s/zstd-1.5.7.tar.gz"
    } > "$WORK/sources.tsv"
}

# fresh_bundle: <WORK>/b/linux-tools-mac with stand-in Mach-O files, and its origins file
fresh_bundle() {
    local b="$WORK/b/linux-tools-mac" f
    rm -rf "$WORK/b"
    mkdir -p "$b/bin" "$b/lib"
    for f in bin/ar bin/gtar bin/lzip lib/libbfd-2.47.dylib lib/libsframe.3.dylib lib/libzstd.1.dylib; do
        printf '\317\372\355\376fixture' > "$b/$f"
    done
    ln -s ar "$b/bin/gar"
    printf 'platform: darwin\n' > "$b/VERSION.txt"
    {
        printf '%s\t%s\n' "$b/bin/gtar" "$CELLAR/gnu-tar/1.35_1/bin/gtar"
        printf '%s\t%s\n' "$b/bin/lzip" "$CELLAR/lzip/1.26/bin/lzip"
        printf '%s\t%s\n' "$b/bin/ar" "$CELLAR/binutils/2.47/bin/ar"
        printf '%s\t%s\n' "$b/lib/libbfd-2.47.dylib" "$CELLAR/binutils/2.47/lib/libbfd-2.47.dylib"
        printf '%s\t%s\n' "$b/lib/libsframe.3.dylib" "$CELLAR/binutils/2.47/lib/libsframe.3.0.0.dylib"
        printf '%s\t%s\n' "$b/lib/libzstd.1.dylib" "$CELLAR/zstd/1.5.7_1/lib/libzstd.1.5.7.dylib"
    } > "$WORK/origins.tsv"
    BUNDLE="$b"
}

collect() {
    bash "$COLLECT" --bundle-dir "$BUNDLE" --origins "$WORK/origins.tsv" --sources "$WORK/sources.tsv" "$@" > "$WORK/out.log" 2>&1
}
verify() {
    bash "$VERIFY" --bundle-dir "$BUNDLE" > "$WORK/out.log" 2>&1
}

# expect_fail <label> <expected text in the output> <command...>
expect_fail() {
    local label="$1" expected="$2"
    shift 2
    if "$@"; then
        bad "accepted: $label"
        sed 's/^/      /' "$WORK/out.log"
    elif grep -qF -- "$expected" "$WORK/out.log"; then
        ok "rejects: $label"
    else
        bad "rejected $label, but without naming \"$expected\""
        sed 's/^/      /' "$WORK/out.log"
    fi
}

echo "🧪 linux-tools-mac license collection / verification self-test"

# ── happy path ──
make_sources
write_sources_tsv
fresh_bundle
if collect && verify; then
    ok "collect-licenses.sh + verify-bundle-licenses.sh pass on a complete bundle"
else
    bad "complete bundle rejected"
    sed 's/^/      /' "$WORK/out.log"
fi
L="$BUNDLE/LICENSES"
expected_manifest="$(printf 'bin/ar\tbinutils\nbin/gtar\tgnu-tar\nbin/lzip\tlzip\nlib/libbfd-2.47.dylib\tbinutils\nlib/libsframe.3.dylib\tbinutils\nlib/libzstd.1.dylib\tzstd')"
if [[ "$(grep -v '^#' "$L/MANIFEST.tsv")" == "$expected_manifest" ]]; then
    ok "MANIFEST.tsv maps every bundled file to its formula"
else
    bad "unexpected MANIFEST.tsv:"; sed 's/^/      /' "$L/MANIFEST.tsv"
fi
if [[ "$(cat "$L/binutils/COPYING3")" == "placeholder COPYING3 for binutils-2.47 (test fixture)" \
    && "$(find "$L/binutils" -type f -exec basename {} \; | sort | tr '\n' ' ')" == "COPYING COPYING.LIB COPYING3 COPYING3.LIB " ]]; then
    ok "binutils COPYING3 / COPYING3.LIB copied from the top of the source tarball (not binutils/COPYING)"
else
    bad "binutils licenses: $(find "$L/binutils" -type f | tr '\n' ' ')"
fi
if [[ "$(cat "$L/zstd/divsufsort-LICENSE")" == "$(printf '/*\n * divsufsort.c (fixture)\n * Copyright (c) fixture\n */')" ]]; then
    ok "zstd divsufsort-LICENSE is the leading comment of lib/dictBuilder/divsufsort.c, verbatim"
else
    bad "divsufsort-LICENSE:"; sed 's/^/      /' "$L/zstd/divsufsort-LICENSE"
fi
if [[ ! -e "$L/gnu-tar/README" ]]; then ok "only the listed files are copied"; else bad "gnu-tar/README copied"; fi
if grep -qx '\[lzip\]' "$L/SOURCES.txt" && grep -qx '  license:  see LICENSES/lzip/' "$L/SOURCES.txt" \
    && grep -qx '  source:   https://example.invalid/binutils-2.47.tar.gz' "$L/SOURCES.txt" \
    && grep -qx "  sha256:   $(sha256_of "$WORK/src/binutils-2.47.tar.gz")" "$L/SOURCES.txt" \
    && grep -qx '  files:    bin/ar lib/libbfd-2.47.dylib lib/libsframe.3.dylib' "$L/SOURCES.txt"; then
    ok "SOURCES.txt lists version, license, URL, sha256 and files per component (empty license column kept apart)"
else
    bad "unexpected SOURCES.txt:"; sed 's/^/      /' "$L/SOURCES.txt"
fi
tr -d '\r' < "$SCRIPT_DIR/license-files.tsv" | sed 's/$/\r/' > "$WORK/license-files-crlf.tsv"
fresh_bundle
if collect --license-files "$WORK/license-files-crlf.tsv"; then ok "CRLF license-files.tsv accepted"; else bad "CRLF license-files.tsv rejected"; fi

# ── collect-licenses.sh must fail ──
echo ""
echo "── collect-licenses.sh must reject ──"
make_tarball binutils-2.47 COPYING COPYING.LIB COPYING3.LIB binutils/COPYING3
write_sources_tsv
fresh_bundle
expect_fail "binutils tarball without a top-level COPYING3" "binutils: COPYING3 not found" collect
make_tarball binutils-2.47 COPYING COPYING.LIB COPYING3 COPYING3.LIB
: > "$WORK/srctree/binutils-2.47/COPYING3"
tar -czf "$WORK/src/binutils-2.47.tar.gz" -C "$WORK/srctree" binutils-2.47
write_sources_tsv
fresh_bundle
expect_fail "empty COPYING3" "COPYING3 is empty" collect
make_sources
write_sources_tsv

awk -F'\t' 'BEGIN { OFS = "\t" } $1 == "zstd" { $4 = "0000000000000000000000000000000000000000000000000000000000000000" } 1' \
    "$WORK/sources.tsv" > "$WORK/sources.bad" && mv "$WORK/sources.bad" "$WORK/sources.tsv"
fresh_bundle
expect_fail "source tarball not matching the pinned sha256" "zstd: $WORK/src/zstd-1.5.7.tar.gz has sha256" collect
write_sources_tsv

fresh_bundle
sed 's#/binutils/2.47/lib/libbfd#/binutils/2.48/lib/libbfd#' "$WORK/origins.tsv" > "$WORK/origins.bad" && mv "$WORK/origins.bad" "$WORK/origins.tsv"
expect_fail "bundled keg version differs from the source tarball" "binutils: the bundled keg is version 2.48" collect

fresh_bundle
printf '\317\372\355\376' > "$BUNDLE/lib/libintl.8.dylib"
printf '%s\t%s\n' "$BUNDLE/lib/libintl.8.dylib" "$CELLAR/gettext/0.26/lib/libintl.8.dylib" >> "$WORK/origins.tsv"
expect_fail "a bundled formula without a license-files.tsv entry" "gettext: bundled (lib/libintl.8.dylib )" collect

fresh_bundle
grep -v '^lzip' "$WORK/sources.tsv" > "$WORK/sources.bad" && mv "$WORK/sources.bad" "$WORK/sources.tsv"
expect_fail "a bundled formula without a source tarball" "lzip: bundled but has no source tarball" collect
write_sources_tsv

printf 'int x; /* Copyright later */\n' > "$WORK/srctree/zstd-1.5.7/lib/dictBuilder/divsufsort.c"
tar -czf "$WORK/src/zstd-1.5.7.tar.gz" -C "$WORK/srctree" zstd-1.5.7
write_sources_tsv
fresh_bundle
expect_fail "divsufsort.c without a leading comment" "does not start with a comment block" collect
make_sources
write_sources_tsv

# ── verify-bundle-licenses.sh must fail ──
echo ""
echo "── verify-bundle-licenses.sh must reject ──"
# tamper <label> <expected> <shell snippet run on $L>
tamper() {
    local label="$1" expected="$2" snippet="$3"
    fresh_bundle
    collect || { bad "setup for: $label"; sed 's/^/      /' "$WORK/out.log"; return 0; }
    (cd "$BUNDLE/LICENSES" && eval "$snippet")
    expect_fail "$label" "$expected" verify
}
tamper "LICENSES/binutils/COPYING3 missing" "LICENSES/binutils/COPYING3: missing or empty" 'rm binutils/COPYING3'
tamper "LICENSES/binutils/COPYING3.LIB empty" "LICENSES/binutils/COPYING3.LIB: missing or empty" ': > binutils/COPYING3.LIB'
tamper "zstd divsufsort-LICENSE missing" "LICENSES/zstd/divsufsort-LICENSE: missing or empty" 'rm zstd/divsufsort-LICENSE'
tamper "lib/libzstd.1.dylib dropped from MANIFEST.tsv" "lib/libzstd.1.dylib: macho binary not listed" \
    'grep -v libzstd MANIFEST.tsv > m && mv m MANIFEST.tsv'
tamper "LICENSES/lzip/ removed" "LICENSES/lzip/: missing" 'rm -r lzip'
tamper "unlicensed extra binary" "bin/extra: macho binary not listed" 'cp ../bin/lzip ../bin/extra'
tamper "a component without a license-files.tsv entry" "gettext: in LICENSES/MANIFEST.tsv but has no entry" \
    'printf "bin/lzip\tgettext\n" >> MANIFEST.tsv && mkdir gettext && echo x > gettext/COPYING'
tamper "LICENSES/EXEMPT.tsv present" "LICENSES/EXEMPT.tsv" 'printf "bin/lzip\tpending\n" > EXEMPT.tsv'
tamper "SOURCES.txt missing" "LICENSES/SOURCES.txt is missing" 'rm SOURCES.txt'
tamper "SOURCES.txt without the binutils sha256" "no \"sha256: <64 hex digits>\" for binutils" \
    'awk "/^\\[binutils\\]/ {f = 1} /^\\[zstd\\]/ {f = 0} !(f && /sha256:/)" SOURCES.txt > s && mv s SOURCES.txt'
tamper "SOURCES.txt without the zstd source URL" "no \"source: <url>\" for zstd" \
    'awk "/^\\[zstd\\]/ {f = 1} !(f && /source:/)" SOURCES.txt > s && mv s SOURCES.txt'

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
