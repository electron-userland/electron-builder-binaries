#!/usr/bin/env bash
# Fails unless every Mach-O file passed in links only against libraries that
# ship with macOS (/usr/lib, /System/Library) or that are bundled next to it.
# Guards against the bundle silently picking up Homebrew (or any other
# non-system) dylibs again.
#
#   - @rpath/<name> references must exist as <lib-dir>/<name>
#   - LC_RPATH entries must be relative to the image (@executable_path / @loader_path)
#   - no embedded Homebrew paths (e.g. a compiled-in dlopen default, which `otool -L` can't see)
#   - with --macos-target, the minimum macOS version (minos) must not be newer than <ver>
#
# Usage: verify-macos-linkage.sh [--lib-dir <bundle lib dir>] [--macos-target <ver>] <mach-o> [<mach-o> ...]
set -euo pipefail

LIB_DIR=""
MACOS_TARGET=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --lib-dir)      LIB_DIR="$2";      shift 2 ;;
        --macos-target) MACOS_TARGET="$2"; shift 2 ;;
        *)              break ;;
    esac
done

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 [--lib-dir <dir>] [--macos-target <ver>] <mach-o> [<mach-o> ...]" >&2
    exit 2
fi

status=0
for bin in "$@"; do
    if [[ ! -f "$bin" ]]; then
        echo "❌ Not found: $bin" >&2
        status=1
        continue
    fi
    echo "🔎 Linked libraries of $bin:"
    # `otool -L` prints the file name first, then one entry per line; for a dylib the
    # first entry is its own install name (LC_ID_DYLIB), which is checked like a dependency.
    deps="$(otool -L "$bin" | awk 'NR>1 {print $1}')"
    if [[ -z "$deps" ]]; then
        echo "❌ otool reported no linked libraries for $bin (not a Mach-O file?)" >&2
        status=1
        continue
    fi
    while IFS= read -r dep; do
        case "$dep" in
            /usr/lib/*|/System/Library/*)
                echo "  ✅ $dep" ;;
            @rpath/*)
                name="${dep#@rpath/}"
                if [[ -n "$LIB_DIR" && -f "$LIB_DIR/$name" ]]; then
                    echo "  ✅ $dep (bundled)"
                else
                    echo "  ❌ $dep (not in bundled lib dir ${LIB_DIR:-<none>})" >&2
                    status=1
                fi
                ;;
            *)
                echo "  ❌ $dep (not part of macOS or the bundle)" >&2
                status=1 ;;
        esac
    done <<< "$deps"

    rpaths="$(otool -l "$bin" | awk '/cmd LC_RPATH/ {getline; getline; print $2}')"
    if [[ -n "$rpaths" ]]; then
        while IFS= read -r rp; do
            case "$rp" in
                @executable_path*|@loader_path*) echo "  ✅ LC_RPATH $rp" ;;
                *) echo "  ❌ LC_RPATH $rp (absolute search path)" >&2; status=1 ;;
            esac
        done <<< "$rpaths"
    fi

    # Narrower than /usr/local/*: osslsigncode legitimately probes /usr/local/share/certs.
    leaks="$(strings -a "$bin" | grep -E '/opt/homebrew/|/usr/local/(Cellar|opt|Homebrew)/' | sort -u || true)"
    if [[ -n "$leaks" ]]; then
        while IFS= read -r leak; do
            echo "  ❌ embedded path $leak" >&2
        done <<< "$leaks"
        status=1
    fi

    if [[ -n "$MACOS_TARGET" ]]; then
        minos="$(otool -l "$bin" | awk '/LC_BUILD_VERSION|LC_VERSION_MIN_MACOSX/{f=1} f && /minos|version/{if (!v) v=$2; f=0} END{print v}')"
        if [[ -z "$minos" ]]; then
            echo "  ❌ no LC_BUILD_VERSION / LC_VERSION_MIN_MACOSX to check against macOS $MACOS_TARGET" >&2
            status=1
        elif awk -v a="$minos" -v b="$MACOS_TARGET" \
                'BEGIN{split(a,A,"."); split(b,B,"."); if (A[1]+0>B[1]+0 || (A[1]+0==B[1]+0 && A[2]+0>B[2]+0)) exit 1}'; then
            echo "  ✅ minos $minos"
        else
            echo "  ❌ minos $minos is newer than macOS $MACOS_TARGET" >&2
            status=1
        fi
    fi
done

if [[ $status -ne 0 ]]; then
    echo "❌ Non-system libraries, absolute search paths, embedded Homebrew paths or a too-new minos found (see above)." >&2
fi
exit $status
