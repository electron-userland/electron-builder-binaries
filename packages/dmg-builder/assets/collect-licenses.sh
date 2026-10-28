#!/usr/bin/env bash
# =============================================================================
# collect-licenses.sh: lay out LICENSES/ in a dmg-builder bundle for scripts/verify-licenses.sh
# =============================================================================
#
#   collect-licenses.sh dist-info <site-packages> <licenses-dir> [--skip <name>]... [--no-license-ok <name>]...
#       Copy the license files of every installed Python distribution (<name>-<ver>.dist-info/licenses/**, and
#       LICENSE* / LICENCE* / COPYING* / NOTICE* / AUTHORS* at the top of the .dist-info) into
#       <licenses-dir>/<Name>/, Name being the "Name:" field of its METADATA. Must run before the build deletes the
#       .dist-info directories. Fails when a distribution has no license file, unless it is passed with
#       --no-license-ok (the caller then supplies it, e.g. pyobjc-core, whose wheel has none). --skip ignores a
#       distribution whose license the caller takes from elsewhere (dmgbuild: fetched at the pinned commit).
#
#   collect-licenses.sh cpython <python-source-dir> <licenses-dir>
#       Copy CPython's LICENSE, its notices for the third-party code built into the interpreter and extension
#       modules (Doc/license.rst, "Licenses and Acknowledgements for Incorporated Software": expat, libmpdec,
#       mimalloc, Mersenne Twister, ...), and the MIT notice of HACL* (the hash modules), which license.rst does not
#       include and which lives in the header of the HACL* sources, into <licenses-dir>/python/.
#
#   collect-licenses.sh manifest <bundle-dir>
#       Write <bundle-dir>/LICENSES/MANIFEST.tsv for the bundle layout (python/lib/python3.X/...).
#
# Portable bash (macOS bash 3.2 and Linux).
# =============================================================================
set -euo pipefail

die() {
    echo "❌ $*" >&2
    exit 1
}

usage() {
    sed -n '5,20p' "$0" >&2
    exit 2
}

# copy_license <src> <dest-dir>: a license file, never executable (the build signs every executable file)
copy_license() {
    mkdir -p "$2"
    cp "$1" "$2/"
    chmod 0644 "$2/$(basename "$1")"
}

cmd_dist_info() {
    [ $# -ge 2 ] || usage
    local site="$1" out="$2" skip=" " no_license_ok=" " di name dest f found missing=""
    shift 2
    while [ $# -gt 0 ]; do
        case "$1" in
            --skip) [ $# -ge 2 ] || usage; skip="$skip$2 "; shift 2 ;;
            --no-license-ok) [ $# -ge 2 ] || usage; no_license_ok="$no_license_ok$2 "; shift 2 ;;
            *) usage ;;
        esac
    done
    [ -d "$site" ] || die "Not a directory: $site"

    local count=0
    for di in "$site"/*.dist-info; do
        [ -d "$di" ] || continue
        [ -f "$di/METADATA" ] || die "$di has no METADATA"
        name=$(sed -n 's/^Name:[[:space:]]*//p' "$di/METADATA" | head -n 1 | tr -d '\r')
        case "$name" in
            ''|.|..|*[!A-Za-z0-9._-]*) die "$di/METADATA: unexpected distribution name '$name'" ;;
        esac
        case "$skip" in *" $name "*) echo "  - $name: skipped (license collected separately)"; continue ;; esac
        dest="$out/$name"
        found=0
        if [ -d "$di/licenses" ]; then
            # PEP 639: license files keep their relative paths under .dist-info/licenses/
            while IFS= read -r -d '' f; do
                rel="${f#"$di/licenses/"}"
                copy_license "$f" "$dest/$(dirname "$rel")"
                found=$((found + 1))
            done < <(find "$di/licenses" -type f -print0)
        fi
        for f in "$di"/LICENSE* "$di"/LICENCE* "$di"/COPYING* "$di"/NOTICE* "$di"/AUTHORS*; do
            [ -f "$f" ] || continue
            copy_license "$f" "$dest"
            found=$((found + 1))
        done
        count=$((count + 1))
        if [ "$found" -gt 0 ]; then
            echo "  ✓ $name: $found license file(s)"
        else
            case "$no_license_ok" in
                *" $name "*) echo "  - $name: no license file in its .dist-info (supplied separately)" ;;
                *) missing="$missing $name" ;;
            esac
        fi
    done
    [ "$count" -gt 0 ] || die "No .dist-info directories in $site"
    [ -z "$missing" ] || die "No license file in the .dist-info of:$missing"
}

cmd_cpython() {
    [ $# -eq 2 ] || usage
    local src="$1" out="$2/python" hacl="$1/Modules/_hacl/Hacl_Hash_SHA2.c"
    [ -f "$src/LICENSE" ] || die "$src/LICENSE not found"
    [ -f "$src/Doc/license.rst" ] || die "$src/Doc/license.rst not found"
    grep -q '^Licenses and Acknowledgements for Incorporated Software' "$src/Doc/license.rst" \
        || die "$src/Doc/license.rst has no 'Licenses and Acknowledgements for Incorporated Software' section"
    [ -f "$hacl" ] || die "$hacl not found (the HACL* notice is taken from its header)"

    copy_license "$src/LICENSE" "$out"
    copy_license "$src/Doc/license.rst" "$out"
    # The MIT notice is the leading comment of every HACL* source file
    awk '{ print } /\*\// { exit }' "$hacl" > "$out/HACL-star-LICENSE.txt"
    if ! head -n 1 "$out/HACL-star-LICENSE.txt" | grep -q '^/\* MIT License' \
        || ! grep -q 'Copyright' "$out/HACL-star-LICENSE.txt"; then
        die "$hacl does not start with the HACL* MIT License notice"
    fi
    chmod 0644 "$out/HACL-star-LICENSE.txt"
    echo "  ✓ python: LICENSE, license.rst, HACL-star-LICENSE.txt"
}

cmd_manifest() {
    [ $# -eq 1 ] || usage
    local bundle="$1" pylib="" d
    for d in "$bundle"/python/lib/python3.*; do
        [ -d "$d" ] || continue
        [ -z "$pylib" ] || die "More than one python3.* directory in $bundle/python/lib"
        pylib="python/lib/$(basename "$d")"
    done
    [ -n "$pylib" ] || die "No python/lib/python3.* directory in $bundle"
    local site="$pylib/site-packages"
    mkdir -p "$bundle/LICENSES"
    cat > "$bundle/LICENSES/MANIFEST.tsv" <<EOF
# <path or glob in this bundle><TAB><component>: the license files of <component> are in LICENSES/<component>/.
# Checked by scripts/verify-licenses.sh in electron-userland/electron-builder-binaries.

# CPython: the interpreter and its extension modules. LICENSES/python/license.rst carries the notices of the
# third-party code compiled into them (expat, libmpdec, mimalloc, Mersenne Twister, ...), HACL-star-LICENSE.txt
# the one of HACL* (_sha2, _blake2, _hmac, ...).
python/bin/python3*	python
${pylib}/config-*/*.o	python
${pylib}/lib-dynload/*.so	python

# OpenSSL, loaded by _ssl and _hashlib
${pylib}/lib-dynload/libcrypto.*.dylib	openssl
${pylib}/lib-dynload/libssl.*.dylib	openssl

# PyObjC extension modules
${site}/objc/*.so	pyobjc-core
${site}/AppKit/*.so	pyobjc-framework-Cocoa
${site}/CoreFoundation/*.so	pyobjc-framework-Cocoa
${site}/Foundation/*.so	pyobjc-framework-Cocoa
${site}/Quartz/*.so	pyobjc-framework-Quartz

# Pure-Python packages (no binaries; listed so that the check fails if their licenses go missing)
dmgbuild	dmgbuild
${site}/dmgbuild	dmgbuild
${site}/ds_store	ds_store
${site}/mac_alias	mac_alias
EOF
    echo "  ✓ LICENSES/MANIFEST.tsv written ($pylib)"
}

[ $# -ge 1 ] || usage
cmd="$1"
shift
case "$cmd" in
    dist-info) cmd_dist_info "$@" ;;
    cpython)   cmd_cpython "$@" ;;
    manifest)  cmd_manifest "$@" ;;
    *) usage ;;
esac
