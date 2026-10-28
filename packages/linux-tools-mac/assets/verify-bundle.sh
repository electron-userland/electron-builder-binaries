#!/usr/bin/env bash
# Static checks for an (extracted) linux-tools-mac bundle. Fails if:
#   - bin/ holds anything other than the expected tools
#   - any Mach-O loads a non-system dylib that does not resolve inside the bundle
#     (absolute Homebrew paths, @executable_path, unresolvable @rpath/@loader_path)
#   - any Mach-O requires a newer macOS than --max-minos (electron-builder#10084)
#   - any Mach-O has an invalid code signature
#   - lib/ holds a dylib nothing in the bundle loads
#   - verify-bundle-licenses.sh fails: a binary without LICENSES/MANIFEST.tsv entry or license texts (shared
#     scripts/verify-licenses.sh guard), a required license text missing (license-files.tsv), or no SOURCES.txt entry
set -euo pipefail

BUNDLE_DIR=""
MAX_MINOS="15.0"
# Keep in sync with FORMULA_BINS in assets/build-mac.sh (gar is a symlink to ar)
EXPECTED_BINS="ar gar gtar lzip"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bundle-dir) BUNDLE_DIR="$2"; shift 2 ;;
        --max-minos)  MAX_MINOS="$2";  shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

if [[ -z "$BUNDLE_DIR" || ! -d "$BUNDLE_DIR/bin" ]]; then
    echo "Usage: $0 --bundle-dir <path-to-extracted-bundle> [--max-minos 15.0]"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(cd "$BUNDLE_DIR" && pwd -P)"
errors=0
err() { echo "  ❌ $*"; errors=$((errors + 1)); }

is_macho() { file -b "$1" 2>/dev/null | grep -q '^Mach-O'; }

# a <= b for dotted versions
version_le() {
    awk -v a="$1" -v b="$2" 'BEGIN {
        n = split(a, x, "."); m = split(b, y, "."); if (m > n) n = m
        for (i = 1; i <= n; i++) { if ((x[i] + 0) < (y[i] + 0)) exit 0; if ((x[i] + 0) > (y[i] + 0)) exit 1 }
        exit 0 }'
}

macho_deps() {
    otool -arch all -l "$1" 2>/dev/null | awk '
        /cmd LC_(LOAD_DYLIB|LOAD_WEAK_DYLIB|REEXPORT_DYLIB|LAZY_LOAD_DYLIB|LOAD_UPWARD_DYLIB)$/ { f = 1; next }
        f && $1 == "name" { print $2; f = 0 }' | sort -u
}

macho_rpaths() {
    otool -arch all -l "$1" 2>/dev/null | awk '/cmd LC_RPATH$/ { f = 1; next } f && $1 == "path" { print $2; f = 0 }' | sort -u
}

macho_minos() {
    otool -arch all -l "$1" 2>/dev/null | awk '
        /cmd LC_BUILD_VERSION$/      { b = 1; next }
        /cmd LC_VERSION_MIN_MACOSX$/ { v = 1; next }
        b && $1 == "minos"   { print $2; b = 0 }
        v && $1 == "version" { print $2; v = 0 }'
}

# Print the in-bundle real path a dependency resolves to, or nothing
resolve_in_bundle() {
    local dep="$1" file="$2"
    local dir candidate rp real
    dir="$(dirname "$file")"
    case "$dep" in
        @loader_path/*)
            candidate="$dir/${dep#@loader_path/}"
            ;;
        @rpath/*)
            while read -r rp; do
                [[ "$rp" == @loader_path* ]] || continue
                candidate="${rp/#@loader_path/$dir}/${dep#@rpath/}"
                [[ -e "$candidate" ]] && break
                candidate=""
            done < <(macho_rpaths "$file")
            ;;
        *)
            # absolute non-system paths and @executable_path are never acceptable
            return 0
            ;;
    esac
    [[ -n "${candidate:-}" && -e "$candidate" ]] || return 0
    real="$(realpath "$candidate")"
    [[ "$real" == "$BUNDLE_DIR"/* ]] && echo "$real"
    return 0
}

echo "🔎 Verifying bundle: $BUNDLE_DIR (max minos $MAX_MINOS)"

# ── bin/ allowlist ──
actual_bins="$(find "$BUNDLE_DIR/bin" -mindepth 1 -maxdepth 1 -exec basename {} \; | sort | tr '\n' ' ' | sed 's/ $//')"
expected_bins="$(tr ' ' '\n' <<< "$EXPECTED_BINS" | sort | tr '\n' ' ' | sed 's/ $//')"
if [[ "$actual_bins" == "$expected_bins" ]]; then
    echo "  ✅ bin/ contains exactly: $actual_bins"
else
    err "bin/ contains [$actual_bins], expected [$expected_bins]"
fi

# ── every Mach-O file ──
REFERENCED="$(mktemp)"
trap 'rm -f "$REFERENCED"' EXIT

macho_count=0
while read -r f; do
    is_macho "$f" || continue
    macho_count=$((macho_count + 1))
    rel="${f#"$BUNDLE_DIR"/}"

    minos_list="$(macho_minos "$f")"
    if [[ -z "$minos_list" ]]; then
        err "$rel: no LC_BUILD_VERSION / LC_VERSION_MIN_MACOSX"
    fi
    for m in $minos_list; do
        if version_le "$m" "$MAX_MINOS"; then
            echo "  ✅ $rel: minos $m"
        else
            err "$rel: minos $m > $MAX_MINOS"
        fi
    done

    while read -r dep; do
        [[ -z "$dep" ]] && continue
        if [[ "$dep" == /usr/lib/* || "$dep" == /System/Library/* ]]; then
            continue
        fi
        resolved="$(resolve_in_bundle "$dep" "$f")"
        if [[ -n "$resolved" ]]; then
            echo "  ✅ $rel -> $dep"
            echo "$resolved" >> "$REFERENCED"
        else
            err "$rel: $dep does not resolve inside the bundle"
        fi
    done < <(macho_deps "$f")

    if ! codesign --verify --strict "$f" 2>/dev/null; then
        err "$rel: invalid code signature"
    fi
done < <(find "$BUNDLE_DIR/bin" "$BUNDLE_DIR/lib" -type f 2>/dev/null)

if [[ "$macho_count" -eq 0 ]]; then
    err "no Mach-O files found"
fi

# ── no orphan dylibs ──
if [[ -d "$BUNDLE_DIR/lib" ]]; then
    while read -r lib; do
        real="$(realpath "$lib")"
        if ! grep -qxF "$real" "$REFERENCED"; then
            err "lib/$(basename "$lib") is not loaded by anything in the bundle"
        fi
    done < <(find "$BUNDLE_DIR/lib" -type f)
fi

# ── licenses ──
if ! bash "$SCRIPT_DIR/verify-bundle-licenses.sh" --bundle-dir "$BUNDLE_DIR"; then
    err "license verification failed (see above)"
fi

if [[ "$errors" -ne 0 ]]; then
    echo "❌ Bundle verification failed with $errors error(s)"
    exit 1
fi
echo "✅ Bundle verification passed ($macho_count Mach-O files)"
