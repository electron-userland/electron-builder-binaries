#!/usr/bin/env bash
# Helpers that lay out a bundle's LICENSES/ directory for the shared license guard,
# scripts/verify-licenses.sh (see that script for the full contract):
#
#   LICENSES/MANIFEST.tsv   "<relative path or glob><TAB><component>" for every binary the bundle ships
#   LICENSES/<component>/   the component's license files, copied from its pinned source (never written by hand)
#   LICENSES/EXEMPT.tsv     "<relative path or glob><TAB><reason>" for binaries deliberately shipped without license files
#   LICENSES/SOURCES.tsv    "<component><TAB><version><TAB><origin>": where each component comes from; for the
#                           open-source components, where their source code can be obtained (informational, not
#                           checked by the guard; it is the source pointer for the GPL/LGPL components)
#
# Source this file. Every function takes the bundle's LICENSES directory first and returns non-zero (with a message
# on stderr) instead of exiting, so callers running under `set -e` stop the build.
#
#   license_init     <licenses-dir>
#   license_add      <licenses-dir> <component> <license-file>...
#   license_add_dir  <licenses-dir> <component> <dir>          every file directly in <dir> (e.g. MSYS2 share/licenses/<pkg>)
#   license_map      <licenses-dir> <component> <path-or-glob>...
#   license_exempt   <licenses-dir> <reason> <path-or-glob>...
#   license_source   <licenses-dir> <component> <version> <origin>
#   license_verify   <bundle-dir | bundle.zip>...               run the guard on what ships
#
# Package-specific layouts:
#   osslsigncode_unix_licenses    <licenses-dir> <osslsigncode-src> <openssl-src> <libp11-src>    (macOS / Linux)
#   osslsigncode_windows_licenses <bundle-dir> <osslsigncode-src> <pacman-prefix> <mingw-prefix>  (Windows, MSYS2)
#   msys2_dll_license             <licenses-dir> <pacman-prefix> <mingw-prefix> <bundle-path> <dll>

LICENSES_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The shared guard, at the repository root. Override for a standalone checkout of this package.
VERIFY_LICENSES_SH="${VERIFY_LICENSES_SH:-$LICENSES_SH_DIR/../../../scripts/verify-licenses.sh}"

_license_component_ok() {
    case "$1" in
        ''|.|..|*/*|*\\*|*"$(printf '\t')"*)
            echo "❌ Invalid license component name: '$1'" >&2
            return 1 ;;
    esac
}

license_init() {
    local dir="$1"
    mkdir -p "$dir" || return 1
    if [ ! -f "$dir/MANIFEST.tsv" ]; then
        printf '# <relative path or glob>\t<component>: license files are in LICENSES/<component>/\n' > "$dir/MANIFEST.tsv"
    fi
}

license_add() {
    local dir="$1" component="$2" f
    shift 2
    _license_component_ok "$component" || return 1
    if [ $# -eq 0 ]; then
        echo "❌ license_add: no license files given for $component" >&2
        return 1
    fi
    license_init "$dir" && mkdir -p "$dir/$component" || return 1
    for f in "$@"; do
        if [ ! -f "$f" ] || [ ! -s "$f" ]; then
            echo "❌ License file for $component is missing or empty: $f" >&2
            return 1
        fi
        cp "$f" "$dir/$component/" || return 1
    done
}

license_add_dir() {
    local dir="$1" component="$2" src="$3" f found=0
    if [ ! -d "$src" ]; then
        echo "❌ License directory for $component not found: $src" >&2
        return 1
    fi
    for f in "$src"/*; do
        [ -f "$f" ] || continue
        license_add "$dir" "$component" "$f" || return 1
        found=1
    done
    if [ "$found" -eq 0 ]; then
        echo "❌ License directory for $component has no files: $src" >&2
        return 1
    fi
}

license_map() {
    local dir="$1" component="$2" path
    shift 2
    _license_component_ok "$component" || return 1
    license_init "$dir"
    for path in "$@"; do
        printf '%s\t%s\n' "$path" "$component" >> "$dir/MANIFEST.tsv"
    done
}

license_exempt() {
    local dir="$1" reason="$2" path
    shift 2
    if [ -z "$reason" ]; then
        echo "❌ license_exempt: a reason is required" >&2
        return 1
    fi
    license_init "$dir"
    if [ ! -f "$dir/EXEMPT.tsv" ]; then
        printf '# <relative path or glob>\t<reason>: binaries shipped WITHOUT license files\n' > "$dir/EXEMPT.tsv"
    fi
    for path in "$@"; do
        printf '%s\t%s\n' "$path" "$reason" >> "$dir/EXEMPT.tsv"
    done
}

license_source() {
    local dir="$1" component="$2" version="$3" origin="$4"
    _license_component_ok "$component" || return 1
    license_init "$dir"
    if [ ! -f "$dir/SOURCES.tsv" ]; then
        printf '# <component>\t<version>\t<origin (source code of the open-source components)>\n' > "$dir/SOURCES.tsv"
    fi
    # One line per component
    if ! cut -f1 "$dir/SOURCES.tsv" | grep -qxF -- "$component"; then
        printf '%s\t%s\t%s\n' "$component" "$version" "$origin" >> "$dir/SOURCES.tsv"
    fi
}

license_verify() {
    local target status tmp
    if [ ! -f "$VERIFY_LICENSES_SH" ]; then
        echo "❌ License guard not found: $VERIFY_LICENSES_SH (set VERIFY_LICENSES_SH)" >&2
        return 2
    fi
    for target in "$@"; do
        if [ -d "$target" ]; then
            bash "$VERIFY_LICENSES_SH" "$target" || return $?
        elif [ -f "$target" ]; then
            tmp="$(mktemp -d "${TMPDIR:-/tmp}/win-codesign-licenses.XXXXXX")"
            if ! unzip -q "$target" -d "$tmp"; then
                rm -rf "$tmp"
                echo "❌ Cannot extract $target" >&2
                return 2
            fi
            echo "📦 $target"
            status=0
            bash "$VERIFY_LICENSES_SH" "$tmp" || status=$?
            rm -rf "$tmp"
            [ "$status" -eq 0 ] || return "$status"
        else
            echo "❌ Not a bundle directory or zip: $target" >&2
            return 2
        fi
    done
}

# ── osslsigncode (macOS / Linux) ──────────────────────────────────────────────
# osslsigncode (GPL-3.0-or-later with an OpenSSL exception) linked against the bundled OpenSSL (Apache-2.0) and
# libp11's pkcs11prov (LGPL-2.1-or-later). License files come from the sources the binaries were built from: the
# osslsigncode clone at the $OSSLSIGNCODE_VER tag and the SHA-256 pinned OpenSSL / libp11 release tarballs.
# Reads OSSLSIGNCODE_VER, OPENSSL_VER and LIBP11_VER.
osslsigncode_unix_licenses() {
    local dir="$1" ossl_src="$2" openssl_src="$3" libp11_src="$4"
    license_init "$dir" &&
    license_add "$dir" osslsigncode "$ossl_src/LICENSE.txt" "$ossl_src/COPYING.txt" &&
    license_map "$dir" osslsigncode bin/osslsigncode &&
    license_source "$dir" osslsigncode "$OSSLSIGNCODE_VER" \
        "https://github.com/mtrojnar/osslsigncode/tree/$OSSLSIGNCODE_VER" &&
    license_add "$dir" openssl "$openssl_src/LICENSE.txt" &&
    license_map "$dir" openssl 'lib/libcrypto.*' 'lib/libssl.*' &&
    license_source "$dir" openssl "$OPENSSL_VER" \
        "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VER/openssl-$OPENSSL_VER.tar.gz" &&
    license_add "$dir" libp11 "$libp11_src/COPYING" &&
    license_map "$dir" libp11 'lib/ossl-modules/pkcs11prov.*' &&
    license_source "$dir" libp11 "$LIBP11_VER" \
        "https://github.com/OpenSC/libp11/releases/download/libp11-$LIBP11_VER/libp11-$LIBP11_VER.tar.gz"
}

# ── osslsigncode (Windows) ────────────────────────────────────────────────────
# osslsigncode_windows_licenses <bundle-dir> <osslsigncode-src> <pacman-prefix> <mingw-prefix>
# For a bundle with bin/osslsigncode.exe and the MSYS2 DLLs it loads (copied from <mingw-prefix>/bin):
#   - osslsigncode: LICENSE.txt + COPYING.txt from the clone of the $OSSLSIGNCODE_VER tag
#   - openssl: on Windows osslsigncode.exe also compiles in OpenSSL's applink.c (Apache-2.0)
#   - every bin/*.dll: the license files of the MSYS2 package that owns it (openssl, zlib, ...)
# Reads OSSLSIGNCODE_VER.
osslsigncode_windows_licenses() {
    local bundle="$1" ossl_src="$2" pacman_prefix="$3" mingw_prefix="$4" dir dll
    dir="$bundle/LICENSES"
    license_init "$dir" &&
    license_add "$dir" osslsigncode "$ossl_src/LICENSE.txt" "$ossl_src/COPYING.txt" &&
    license_map "$dir" osslsigncode bin/osslsigncode.exe &&
    license_source "$dir" osslsigncode "$OSSLSIGNCODE_VER" \
        "https://github.com/mtrojnar/osslsigncode/tree/$OSSLSIGNCODE_VER" &&
    license_add_dir "$dir" openssl "$mingw_prefix/share/licenses/openssl" &&
    license_map "$dir" openssl bin/osslsigncode.exe || return 1
    for dll in "$bundle"/bin/*.dll; do
        [ -f "$dll" ] || continue
        msys2_dll_license "$dir" "$pacman_prefix" "$mingw_prefix" "bin/${dll##*/}" "$mingw_prefix/bin/${dll##*/}" ||
            return 1
    done
}

# ── MSYS2 DLLs (Windows) ──────────────────────────────────────────────────────
# msys2_dll_license <licenses-dir> <pacman-prefix> <mingw-prefix> <bundle-path> <dll>
# Finds the MSYS2 package that owns <dll> (e.g. mingw-w64-x86_64-openssl), and ships the license files that package
# installs in <mingw-prefix>/share/licenses/<name>/ as component <name>, for <bundle-path> in the bundle.
msys2_dll_license() {
    local dir="$1" pacman_prefix="$2" mingw_prefix="$3" bundle_path="$4" dll="$5" pkg component version
    if ! pkg="$(pacman -Qqo "$dll")" || [ -z "$pkg" ]; then
        echo "❌ No MSYS2 package owns $dll, so its license is unknown" >&2
        return 1
    fi
    component="${pkg#"$pacman_prefix"-}"
    version="$(pacman -Q "$pkg" | awk '{print $2}')"
    license_add_dir "$dir" "$component" "$mingw_prefix/share/licenses/$component" &&
    license_map "$dir" "$component" "$bundle_path" &&
    license_source "$dir" "$component" "${version:-unknown}" "MSYS2 package $pkg (https://packages.msys2.org/)"
}
