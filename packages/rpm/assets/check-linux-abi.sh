#!/usr/bin/env bash
# Usage: check-linux-abi.sh <bundle-dir>
# Prints the highest GLIBC_/GLIBCXX_/CXXABI_/GCC_ symbol versions required by any ELF in the
# bundle and fails if one exceeds the ceiling from constants.sh (MAX_GLIBC etc.).
set -euo pipefail

ASSETS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=SCRIPTDIR/constants.sh
source "$ASSETS/constants.sh"
BUNDLE="${1:?usage: check-linux-abi.sh <bundle-dir>}"

syms=$(find "$BUNDLE" -type f -print0 | while IFS= read -r -d '' f; do
    if [ "$(head -c 4 "$f" | od -An -tx1 | tr -d ' \n')" = "7f454c46" ]; then
        objdump -T "$f" 2>/dev/null | grep -oE '\b(GLIBC|GLIBCXX|CXXABI|GCC)_[0-9][0-9.]*' || true
    fi
done | sort -u)

max_of() { printf '%s\n' "$syms" | sed -n "s/^$1_//p" | sort -V | tail -1; }
# version_gt a b: true when a > b
version_gt() { [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]; }

status=0
check() {
    local name="$1" limit="$2" found
    found=$(max_of "$name")
    if [ -z "$found" ]; then
        echo "max-$name: none"
    elif [ -n "$limit" ] && version_gt "$found" "$limit"; then
        echo "max-$name: $found (❌ exceeds $limit)"
        status=1
    else
        echo "max-$name: $found${limit:+ (<= $limit)}"
    fi
}
check GLIBC "$MAX_GLIBC"
check GLIBCXX "$MAX_GLIBCXX"
check CXXABI "$MAX_CXXABI"
check GCC ""
if [ "$status" != "0" ]; then
    echo "Offending files:" >&2
    find "$BUNDLE" -type f | while read -r f; do
        objdump -T "$f" 2>/dev/null | grep -oE "\bGLIBC_$(max_of GLIBC)\b" | head -1 | sed "s|^|  $f: |" >&2 || true
    done
fi
exit "$status"
