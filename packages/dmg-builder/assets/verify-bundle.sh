#!/usr/bin/env bash
# Fails unless every Mach-O file in a dmg-builder bundle
#   - links no library from Homebrew (/usr/local/..., /opt/homebrew/...), and
#   - has a minimum macOS version (minos) no newer than --macos-target.
#
# Each argument is a bundle directory or a .tar.gz of one (the archive is
# extracted to a temp dir first, so the check covers exactly what ships).
# A bundle with no Mach-O files at all is an error: an earlier version of this
# check scanned a directory that only held the tarball and passed vacuously.
#
# Usage: verify-bundle.sh --macos-target <ver> <dir|archive.tar.gz> [...]
set -euo pipefail

MACOS_TARGET=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --macos-target) MACOS_TARGET="$2"; shift 2 ;;
        --) shift; break ;;
        -*) echo "Unknown argument: $1" >&2; exit 2 ;;
        *)  break ;;
    esac
done

if [[ -z "$MACOS_TARGET" || $# -eq 0 ]]; then
    echo "Usage: $0 --macos-target <ver> <dir|archive.tar.gz> [...]" >&2
    exit 2
fi

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# Exit 0 when version $1 is newer than version $2 (compares up to X.Y.Z).
version_gt() {
    awk -v a="$1" -v b="$2" 'BEGIN {
        n = split(a, A, "."); m = split(b, B, ".")
        for (i = 1; i <= 3; i++) {
            x = (i <= n) ? A[i] + 0 : 0; y = (i <= m) ? B[i] + 0 : 0
            if (x > y) exit 0
            if (x < y) exit 1
        }
        exit 1
    }'
}

# Print every minimum-OS version recorded in a Mach-O (all slices of a fat file):
# "minos" of LC_BUILD_VERSION, or "version" of the older LC_VERSION_MIN_MACOSX.
macho_minos() {
    otool -arch all -l "$1" 2>/dev/null | awk '
        $1 == "cmd" { cmd = $2; next }
        cmd == "LC_BUILD_VERSION"      && $1 == "minos"   { print $2 }
        cmd == "LC_VERSION_MIN_MACOSX" && $1 == "version" { print $2 }
    '
}

status=0
for target in "$@"; do
    dir="$target"
    if [[ -f "$target" ]]; then
        dir="$(mktemp -d "$TMP_ROOT/bundle.XXXXXX")"
        tar -xzf "$target" -C "$dir"
    elif [[ ! -d "$target" ]]; then
        echo "❌ Not found: $target" >&2
        status=1
        continue
    fi

    echo "🔎 Checking $target (macOS >= ${MACOS_TARGET}, no Homebrew links)"
    checked=0
    while IFS= read -r -d '' f; do
        [[ "$(file -b "$f")" == *Mach-O* ]] || continue
        checked=$((checked + 1))
        rel="${f#"$dir"/}"

        leaks="$(otool -arch all -L "$f" 2>/dev/null | awk '/^[[:space:]]/ && $1 ~ /^(\/usr\/local\/|\/opt\/homebrew\/)/ {print $1}' | sort -u)"
        if [[ -n "$leaks" ]]; then
            while IFS= read -r leak; do
                echo "  ❌ $rel links Homebrew library $leak" >&2
            done <<< "$leaks"
            status=1
        fi

        versions="$(macho_minos "$f")"
        if [[ -z "$versions" ]]; then
            echo "  ❌ $rel has no LC_BUILD_VERSION / LC_VERSION_MIN_MACOSX" >&2
            status=1
            continue
        fi
        while IFS= read -r v; do
            if version_gt "$v" "$MACOS_TARGET"; then
                echo "  ❌ $rel has minos $v, newer than macOS ${MACOS_TARGET}" >&2
                status=1
            fi
        done <<< "$versions"
    done < <(find "$dir" -type f -print0)

    if [[ $checked -eq 0 ]]; then
        echo "  ❌ no Mach-O files found in $target" >&2
        status=1
    else
        echo "  ✓ inspected $checked Mach-O files"
    fi
done

if [[ $status -ne 0 ]]; then
    echo "🛑 Bundle rejected: Homebrew links, a too-new minos, or nothing to check (see above)." >&2
fi
exit $status
