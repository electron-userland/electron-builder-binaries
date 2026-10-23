#!/usr/bin/env bash
# Fails unless every Mach-O file passed in links only against libraries that
# ship with macOS (/usr/lib, /System/Library). Guards against the bundle
# silently picking up Homebrew (or any other non-system) dylibs again.
#
# Usage: verify-macos-linkage.sh <mach-o> [<mach-o> ...]
set -euo pipefail

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <mach-o> [<mach-o> ...]" >&2
    exit 2
fi

is_system_dylib() {
    case "$1" in
        /usr/lib/*|/System/Library/*) return 0 ;;
        *) return 1 ;;
    esac
}

status=0
for bin in "$@"; do
    if [[ ! -f "$bin" ]]; then
        echo "❌ Not found: $bin" >&2
        status=1
        continue
    fi
    echo "🔎 Linked libraries of $bin:"
    # `otool -L` prints the file name first, then one dependency per line.
    deps="$(otool -L "$bin" | awk 'NR>1 {print $1}')"
    if [[ -z "$deps" ]]; then
        echo "❌ otool reported no linked libraries for $bin (not a Mach-O executable?)" >&2
        status=1
        continue
    fi
    while IFS= read -r dep; do
        if is_system_dylib "$dep"; then
            echo "  ✅ $dep"
        else
            echo "  ❌ $dep (not part of macOS)" >&2
            status=1
        fi
    done <<< "$deps"
done

if [[ $status -ne 0 ]]; then
    echo "❌ Non-system dynamic libraries found. Link them statically or bundle them." >&2
fi
exit $status
