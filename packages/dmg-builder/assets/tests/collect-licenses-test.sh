#!/usr/bin/env bash
# Self-test for assets/collect-licenses.sh: lays out LICENSES/ for a fixture bundle shaped like the real one (Mach-O
# files are just magic bytes) and checks that scripts/verify-licenses.sh accepts it, and rejects it once a license, a
# licensed package or a manifest entry goes missing. Fixture "license" files are placeholders. Runs on Linux and macOS.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECT="$HERE/../collect-licenses.sh"
GUARD="$HERE/../../../../scripts/verify-licenses.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

failures=0
pass() { echo "✓ $1"; }
fail() {
    echo "❌ $1"
    [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/     /'
    failures=$((failures + 1))
}
# expect <pass|fail> <description> <grep -E pattern for the output, or ""> <command...>
expect() {
    local want="$1" desc="$2" pattern="$3" out rc=0 got=pass
    shift 3
    out="$("$@" 2>&1)" || rc=$?
    [ "$rc" -eq 0 ] || got=fail
    if [ "$got" != "$want" ]; then
        fail "$desc: expected $want, got $got (exit $rc)" "$out"
    elif [ -n "$pattern" ] && ! grep -qE -- "$pattern" <<< "$out"; then
        fail "$desc: output does not match /$pattern/" "$out"
    else
        pass "$desc"
    fi
}
# same <description> <file> <expected content>
same() {
    if [ -f "$2" ] && [ "$(cat "$2")" = "$3" ]; then pass "$1"; else fail "$1 ($2)"; fi
}

macho() { mkdir -p "$(dirname "$1")"; printf '\317\372\355\376\014\000\000\001' > "$1"; }
text() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; }

# dist_info <site-packages> <dir name> <Name> : a .dist-info with METADATA (CRLF, like some wheels)
dist_info() {
    mkdir -p "$1/$2"
    printf 'Metadata-Version: 2.4\r\nName: %s\r\nVersion: 1.0\r\n' "$3" > "$1/$2/METADATA"
}

# --- site-packages as pip leaves it, before the build deletes the .dist-info directories ---
SITE="$WORK/site-packages"
dist_info "$SITE" ds_store-1.3.3.dist-info ds_store
text "$SITE/ds_store-1.3.3.dist-info/licenses/LICENSE" "ds_store license"
dist_info "$SITE" mac_alias-2.2.3.dist-info mac_alias
text "$SITE/mac_alias-2.2.3.dist-info/licenses/LICENSE" "mac_alias license"
text "$SITE/mac_alias-2.2.3.dist-info/licenses/vendor/sub/COPYING" "nested license"
dist_info "$SITE" pyobjc_core-12.2.2.dist-info pyobjc-core
dist_info "$SITE" pyobjc_framework_cocoa-12.2.2.dist-info pyobjc-framework-Cocoa
text "$SITE/pyobjc_framework_cocoa-12.2.2.dist-info/licenses/LICENSE.txt" "cocoa license"
dist_info "$SITE" pyobjc_framework_quartz-12.2.2.dist-info pyobjc-framework-Quartz
# older wheel layout: license at the top of the .dist-info
text "$SITE/pyobjc_framework_quartz-12.2.2.dist-info/LICENSE.txt" "quartz license"
text "$SITE/pyobjc_framework_quartz-12.2.2.dist-info/RECORD" "not a license"
dist_info "$SITE" dmgbuild-1.6.7.dist-info dmgbuild
text "$SITE/dmgbuild-1.6.7.dist-info/licenses/LICENSE" "dmgbuild license from the wheel"

# --- CPython source tree ---
PYSRC="$WORK/Python-3.14.10"
text "$PYSRC/LICENSE" "PSF license"
printf 'License\n=======\n\nLicenses and Acknowledgements for Incorporated Software\n=====\n\nexpat ...\n' > "$WORK/license.rst"
mkdir -p "$PYSRC/Doc"
cp "$WORK/license.rst" "$PYSRC/Doc/license.rst"
HACL_HEADER='/* MIT License
 *
 * Copyright (c) 2016-2022 INRIA, CMU and Microsoft Corporation
 */'
mkdir -p "$PYSRC/Modules/_hacl"
printf '%s\n\n\n#include "internal/Hacl_Hash_SHA2.h"\n/* another comment */\n' "$HACL_HEADER" > "$PYSRC/Modules/_hacl/Hacl_Hash_SHA2.c"

# --- the bundle ---
new_bundle() {
    local b="$1" py="$1/python/lib/python3.14" site="$1/python/lib/python3.14/site-packages" f
    macho "$b/python/bin/python3.14"
    ln -s python3.14 "$b/python/bin/python3"
    macho "$py/config-3.14-darwin/python.o"
    text "$py/config-3.14-darwin/Makefile" "not a binary"
    for f in _ssl _hashlib _decimal pyexpat _sha2; do macho "$py/lib-dynload/$f.cpython-314-darwin.so"; done
    macho "$py/lib-dynload/libcrypto.3.dylib"
    macho "$py/lib-dynload/libssl.3.dylib"
    macho "$site/objc/_objc.cpython-314-darwin.so"
    macho "$site/AppKit/_AppKit.cpython-314-darwin.so"
    macho "$site/CoreFoundation/_CoreFoundation.cpython-314-darwin.so"
    macho "$site/Foundation/_Foundation.cpython-314-darwin.so"
    macho "$site/Quartz/CoreGraphics/_coregraphics.cpython-314-darwin.so"
    for f in dmgbuild ds_store mac_alias; do text "$site/$f/__init__.py" "# $f"; done
    text "$b/dmgbuild" '#!/bin/bash'
    text "$b/VERSION.txt" "Python version: 3.14.10"
}

# full_layout <bundle>: what build-python-runtime.sh does
full_layout() {
    local b="$1"
    new_bundle "$b"
    bash "$COLLECT" dist-info "$SITE" "$b/LICENSES" --skip dmgbuild --no-license-ok pyobjc-core
    bash "$COLLECT" cpython "$PYSRC" "$b/LICENSES"
    text "$b/LICENSES/openssl/LICENSE.txt" "openssl license"
    text "$b/LICENSES/dmgbuild/LICENSE" "dmgbuild license at the pinned commit"
    text "$b/LICENSES/pyobjc-core/License.txt" "pyobjc-core license from the sdist"
    bash "$COLLECT" manifest "$b"
}

# 1. dist-info: licenses/ (nested paths kept) and top-level LICENSE*, named after METADATA's Name
L="$WORK/dist-info-out"
expect pass "dist-info collects every package license" "pyobjc-core: no license file" \
    bash "$COLLECT" dist-info "$SITE" "$L" --skip dmgbuild --no-license-ok pyobjc-core
same "ds_store LICENSE copied" "$L/ds_store/LICENSE" "ds_store license"
same "nested PEP 639 path kept" "$L/mac_alias/vendor/sub/COPYING" "nested license"
same "Name taken from METADATA, CR stripped" "$L/pyobjc-framework-Cocoa/LICENSE.txt" "cocoa license"
same "top-level .dist-info LICENSE copied" "$L/pyobjc-framework-Quartz/LICENSE.txt" "quartz license"
if [ ! -e "$L/pyobjc-framework-Quartz/RECORD" ]; then pass "non-license .dist-info files not copied"; else fail "RECORD copied"; fi
if [ ! -e "$L/dmgbuild" ]; then pass "--skip leaves dmgbuild out"; else fail "--skip ignored: $L/dmgbuild exists"; fi
if [ -z "$(find "$L" -type f -perm -u+x)" ]; then pass "copied licenses are not executable"; else fail "executable license files"; fi

# 2. dist-info failures
expect fail "a package with no license file fails" "No license file in the .dist-info of: pyobjc-core" \
    bash "$COLLECT" dist-info "$SITE" "$WORK/out2" --skip dmgbuild
mkdir -p "$WORK/empty-site"
expect fail "no .dist-info at all fails" "No .dist-info directories" \
    bash "$COLLECT" dist-info "$WORK/empty-site" "$WORK/out3"
dist_info "$WORK/bad-site" evil-1.0.dist-info "../evil"
expect fail "a distribution name with a / fails" "unexpected distribution name" \
    bash "$COLLECT" dist-info "$WORK/bad-site" "$WORK/out4"

# 3. cpython
expect pass "cpython collects LICENSE, license.rst and the HACL* notice" "" \
    bash "$COLLECT" cpython "$PYSRC" "$WORK/cpy"
same "CPython LICENSE copied" "$WORK/cpy/python/LICENSE" "PSF license"
same "Doc/license.rst copied" "$WORK/cpy/python/license.rst" "$(cat "$WORK/license.rst")"
same "HACL* notice is exactly the leading comment" "$WORK/cpy/python/HACL-star-LICENSE.txt" "$HACL_HEADER"
cp -R "$PYSRC" "$WORK/no-rst" && rm "$WORK/no-rst/Doc/license.rst"
expect fail "a missing Doc/license.rst fails" "license.rst not found" bash "$COLLECT" cpython "$WORK/no-rst" "$WORK/cpy2"
cp -R "$PYSRC" "$WORK/no-ack" && printf 'License\n' > "$WORK/no-ack/Doc/license.rst"
expect fail "license.rst without the third-party section fails" "Incorporated Software" \
    bash "$COLLECT" cpython "$WORK/no-ack" "$WORK/cpy3"
cp -R "$PYSRC" "$WORK/no-hacl" && printf '#include <x.h>\n' > "$WORK/no-hacl/Modules/_hacl/Hacl_Hash_SHA2.c"
expect fail "a HACL* source without the MIT notice fails" "HACL\* MIT License" \
    bash "$COLLECT" cpython "$WORK/no-hacl" "$WORK/cpy4"

# 4. the full layout passes the guard
OK="$WORK/ok"
full_layout "$OK" > /dev/null
expect pass "full layout passes verify-licenses.sh" "All 14 binaries have license files" bash "$GUARD" "$OK"

# 5. ... and the guard catches what goes missing
B="$WORK/no-ds-store-license"
full_layout "$B" > /dev/null && rm -rf "$B/LICENSES/ds_store"
expect fail "missing ds_store license fails" "LICENSES/ds_store/: missing" bash "$GUARD" "$B"

B="$WORK/no-pyobjc-core-license"
full_layout "$B" > /dev/null && rm -f "$B/LICENSES/pyobjc-core/License.txt"
expect fail "missing pyobjc-core license fails" "LICENSES/pyobjc-core/: has no non-empty license file" bash "$GUARD" "$B"

B="$WORK/no-openssl-license"
full_layout "$B" > /dev/null && rm -rf "$B/LICENSES/openssl"
expect fail "missing OpenSSL license fails" "LICENSES/openssl/: missing" bash "$GUARD" "$B"

B="$WORK/extra-binary"
full_layout "$B" > /dev/null && macho "$B/python/lib/python3.14/site-packages/newpkg/_new.cpython-314-darwin.so"
expect fail "an unlisted binary fails" "newpkg/_new.cpython-314-darwin.so: macho binary not listed" bash "$GUARD" "$B"

B="$WORK/renamed-package"
full_layout "$B" > /dev/null && mv "$B/python/lib/python3.14/site-packages/mac_alias" "$B/python/lib/python3.14/site-packages/mac_alias2"
expect fail "a manifest entry for a package that is gone fails" "site-packages/mac_alias: listed in LICENSES/MANIFEST.tsv" \
    bash "$GUARD" "$B"

# 6. manifest follows the Python version and refuses an ambiguous layout
B="$WORK/py315"
full_layout "$B" > /dev/null && mv "$B/python/lib/python3.14" "$B/python/lib/python3.15"
bash "$COLLECT" manifest "$B" > /dev/null
expect pass "manifest follows python/lib/python3.X" "All 14 binaries" bash "$GUARD" "$B"
mkdir -p "$B/python/lib/python3.16"
expect fail "two python3.* directories fail" "More than one python3" bash "$COLLECT" manifest "$B"
expect fail "no python3.* directory fails" "No python/lib/python3" bash "$COLLECT" manifest "$WORK/empty-site"

echo ""
if [ "$failures" -ne 0 ]; then
    echo "❌ $failures collect-licenses test(s) failed"
    exit 1
fi
echo "✅ All collect-licenses tests passed"
