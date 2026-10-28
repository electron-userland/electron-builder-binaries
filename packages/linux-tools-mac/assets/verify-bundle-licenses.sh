#!/usr/bin/env bash
# License checks for an (extracted) linux-tools-mac bundle. Fails (exit 1) unless:
#   - scripts/verify-licenses.sh (the shared guard) passes: every binary is in LICENSES/MANIFEST.tsv and every listed
#     component has a non-empty LICENSES/<component>/
#   - no LICENSES/EXEMPT.tsv: this bundle has no binary whose license is undecided
#   - every component in MANIFEST.tsv has an entry in license-files.tsv and ships every license file and notice that
#     entry requires, non-empty (e.g. binutils COPYING3, zstd divsufsort-LICENSE)
#   - LICENSES/SOURCES.txt names an upstream source URL and a sha256 for every component
# Runs on macOS and Linux.
#
#   verify-bundle-licenses.sh --bundle-dir <dir> [--license-files <file>] [--guard <verify-licenses.sh>]
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR=""
LICENSE_FILES="$SCRIPT_DIR/license-files.tsv"
GUARD="$SCRIPT_DIR/../../../scripts/verify-licenses.sh"

usage() {
    echo "Usage: $0 --bundle-dir <dir> [--license-files <file>] [--guard <verify-licenses.sh>]" >&2
    exit 2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bundle-dir)    BUNDLE_DIR="${2:-}";    shift 2 ;;
        --license-files) LICENSE_FILES="${2:-}"; shift 2 ;;
        --guard)         GUARD="${2:-}";         shift 2 ;;
        *) usage ;;
    esac
done
[[ -n "$BUNDLE_DIR" && -d "$BUNDLE_DIR" && -f "$LICENSE_FILES" ]] || usage
if [[ ! -f "$GUARD" ]]; then
    echo "❌ License guard not found: $GUARD (run from an electron-builder-binaries checkout, or pass --guard)" >&2
    exit 2
fi

LICENSES="$BUNDLE_DIR/LICENSES"
errors=0
err() { echo "  ❌ $*"; errors=$((errors + 1)); }

data_lines() { tr -d '\r' < "$1" | sed -e '/^#/d' -e '/^[[:space:]]*$/d'; }
field() { awk -F'\t' -v n="$2" '{ print $n }' <<< "$1"; }

echo "🔎 Verifying licenses: $BUNDLE_DIR"

# ── shared guard ──
if bash "$GUARD" "$BUNDLE_DIR"; then
    echo "  ✅ scripts/verify-licenses.sh"
else
    err "scripts/verify-licenses.sh failed (see above)"
fi

if [[ -e "$LICENSES/EXEMPT.tsv" ]]; then
    err "LICENSES/EXEMPT.tsv: linux-tools-mac ships no binary without a license, remove the exemption"
fi

# ── required license texts per component ──
components=""
if [[ -f "$LICENSES/MANIFEST.tsv" ]]; then
    components="$(data_lines "$LICENSES/MANIFEST.tsv" | cut -f2 | sort -u)"
fi
[[ -n "$components" ]] || err "LICENSES/MANIFEST.tsv lists no component"

for component in $components; do
    spec="$(data_lines "$LICENSE_FILES" | awk -F'\t' -v f="$component" '$1 == f')"
    if [[ -z "$spec" ]]; then
        err "$component: in LICENSES/MANIFEST.tsv but has no entry in $(basename "$LICENSE_FILES")"
        continue
    fi
    required="$(field "$spec" 2)"
    for notice in $(field "$spec" 3); do
        required="$required ${notice#*:}"
    done
    for name in $required; do
        if [[ -s "$LICENSES/$component/$name" ]]; then
            echo "  ✅ LICENSES/$component/$name"
        else
            err "LICENSES/$component/$name: missing or empty"
        fi
    done

    # ── SOURCES.txt: "[component]" block with an upstream URL and a sha256 ──
    if [[ ! -f "$LICENSES/SOURCES.txt" ]]; then
        continue
    fi
    block="$(awk -v h="[$component]" '$0 == h { f = 1; next } /^\[/ { f = 0 } f' "$LICENSES/SOURCES.txt")"
    if ! grep -Eq '^ *source: +https?://[^ ]+$' <<< "$block"; then
        err "LICENSES/SOURCES.txt: no \"source: <url>\" for $component"
    fi
    if ! grep -Eq '^ *sha256: +[0-9a-f]{64}$' <<< "$block"; then
        err "LICENSES/SOURCES.txt: no \"sha256: <64 hex digits>\" for $component"
    fi
done
[[ -f "$LICENSES/SOURCES.txt" ]] || err "LICENSES/SOURCES.txt is missing (corresponding-source pointer for the GPL components)"

if [[ "$errors" -ne 0 ]]; then
    echo "❌ License verification failed with $errors error(s)"
    exit 1
fi
echo "✅ License verification passed ($(echo "$components" | tr '\n' ' ' | sed 's/ $//'))"
