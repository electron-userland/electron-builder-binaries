#!/usr/bin/env bash
# Lay out LICENSES/ for a linux-tools-mac bundle (the scripts/verify-licenses.sh contract):
#   LICENSES/<formula>/...   the license texts listed in license-files.tsv, taken from the formula's pinned upstream
#                            source tarball (its sha256 is checked first)
#   LICENSES/MANIFEST.tsv    "<bundle-relative path><TAB><formula>" for every bundled Mach-O file
#   LICENSES/SOURCES.txt     where the corresponding source of every bundled component is (GPL source pointer)
#
# Fails (exit 1) when a bundled file comes from a formula without a license-files.tsv entry or a --sources line,
# when a source tarball does not match its sha256 or its version does not match the bundled keg, or when a license
# text is missing from the tarball or empty. Runs on macOS and Linux (no Homebrew needed: build-mac.sh resolves the
# formulas and fetches the tarballs).
#
#   collect-licenses.sh --bundle-dir <dir> --origins <file> --sources <file> [--license-files <file>]
#
#   --origins   "<bundled path under --bundle-dir><TAB><original file under .../Cellar/<formula>/<keg version>/>"
#   --sources   "<formula><TAB><source version><TAB><url><TAB><sha256><TAB><tarball path><TAB><license><TAB><formula url>"
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR=""
ORIGINS=""
SOURCES=""
LICENSE_FILES="$SCRIPT_DIR/license-files.tsv"

usage() {
    echo "Usage: $0 --bundle-dir <dir> --origins <file> --sources <file> [--license-files <file>]" >&2
    exit 2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bundle-dir)    BUNDLE_DIR="${2:-}";    shift 2 ;;
        --origins)       ORIGINS="${2:-}";       shift 2 ;;
        --sources)       SOURCES="${2:-}";       shift 2 ;;
        --license-files) LICENSE_FILES="${2:-}"; shift 2 ;;
        *) usage ;;
    esac
done
[[ -n "$BUNDLE_DIR" && -d "$BUNDLE_DIR" && -f "$ORIGINS" && -f "$SOURCES" && -f "$LICENSE_FILES" ]] || usage

LICENSES="$BUNDLE_DIR/LICENSES"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/collect-licenses.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

errors=0
err() { echo "  ❌ $*"; errors=$((errors + 1)); }

sha256_of() {
    if command -v sha256sum > /dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

# <tsv> -> its data lines (no comments, blank lines or CR)
data_lines() {
    tr -d '\r' < "$1" | sed -e '/^#/d' -e '/^[[:space:]]*$/d'
}

# field <tab-separated line> <n>: column n (awk, so that empty columns do not shift the others)
field() { awk -F'\t' -v n="$2" '{ print $n }' <<< "$1"; }

# Homebrew formula and keg version (revision suffix "_N" dropped) of a Cellar path
formula_of() { sed -n 's#.*/Cellar/\([^/]*\)/.*#\1#p' <<< "$1"; }
keg_version_of() { sed -n 's#.*/Cellar/[^/]*/\([^/]*\)/.*#\1#p' <<< "$1" | sed 's/_[0-9][0-9]*$//'; }

# Archive member whose path, below the tarball's top-level directory, is exactly <path>
find_member() {
    awk -v p="$1" '{ m = $0; sub(/^\.\//, "", m); i = index(m, "/"); if (i > 0 && substr(m, i + 1) == p) print $0 }' \
        "$WORK/members"
}

echo "📄 Collecting licenses into $LICENSES"
rm -rf "$LICENSES"
mkdir -p "$LICENSES"

### ── bundled file -> formula ──
: > "$WORK/manifest"
while IFS=$'\t' read -r bundled origin; do
    [[ -n "$bundled" ]] || continue
    rel="${bundled#"$BUNDLE_DIR"/}"
    if [[ "$rel" == "$bundled" ]]; then
        err "$bundled: not inside $BUNDLE_DIR"
        continue
    fi
    [[ -e "$bundled" ]] || err "$rel: listed in the origins file but not in the bundle"
    formula="$(formula_of "$origin")"
    if [[ -z "$formula" ]]; then
        err "$rel: cannot tell which Homebrew formula $origin belongs to"
        continue
    fi
    printf '%s\t%s\t%s\n' "$rel" "$formula" "$(keg_version_of "$origin")" >> "$WORK/manifest"
done < "$ORIGINS"
sort -u -o "$WORK/manifest" "$WORK/manifest"
cut -f2 "$WORK/manifest" | sort -u > "$WORK/formulas"

### ── license texts from each formula's source tarball ──
data_lines "$LICENSE_FILES" > "$WORK/license-files"
data_lines "$SOURCES" > "$WORK/sources"

while read -r formula; do
    spec="$(awk -F'\t' -v f="$formula" '$1 == f' "$WORK/license-files")"
    src="$(awk -F'\t' -v f="$formula" '$1 == f' "$WORK/sources")"
    if [[ -z "$spec" ]]; then
        err "$formula: bundled ($(awk -F'\t' -v f="$formula" '$2 == f {print $1}' "$WORK/manifest" | tr '\n' ' ')) but has no entry in $(basename "$LICENSE_FILES")"
        continue
    fi
    if [[ -z "$src" ]]; then
        err "$formula: bundled but has no source tarball in the --sources file"
        continue
    fi
    files="$(field "$spec" 2)"
    notices="$(field "$spec" 3)"
    version="$(field "$src" 2)"
    url="$(field "$src" 3)"
    sha256="$(field "$src" 4)"
    tarball="$(field "$src" 5)"

    # The tarball must be the one the formula pins, and the version the bundled keg was built from
    if [[ ! -f "$tarball" ]]; then
        err "$formula: source tarball $tarball not found"
        continue
    fi
    actual="$(sha256_of "$tarball")"
    if [[ "$actual" != "$sha256" ]]; then
        err "$formula: $tarball has sha256 $actual, the formula pins $sha256"
        continue
    fi
    while read -r keg; do
        [[ "$keg" == "$version" ]] || err "$formula: the bundled keg is version $keg but the source tarball is $version ($url)"
    done < <(awk -F'\t' -v f="$formula" '$2 == f {print $3}' "$WORK/manifest" | sort -u)

    if ! tar -tf "$tarball" > "$WORK/members" 2> "$WORK/tar.err"; then
        err "$formula: cannot list $tarball: $(head -n 1 "$WORK/tar.err")"
        continue
    fi

    dest="$LICENSES/$formula"
    mkdir -p "$dest"
    # Top-level license files, verbatim
    for name in $files; do
        member="$(find_member "$name")"
        if [[ -z "$member" || "$member" == *$'\n'* ]]; then
            err "$formula: $name not found (exactly once) at the top of $(basename "$tarball")"
            continue
        fi
        tar -xOf "$tarball" "$member" > "$dest/$name"
        if [[ -s "$dest/$name" ]]; then
            echo "  📄 $formula/$name  <- $(basename "$tarball"):$member"
        else
            err "$formula: $member is empty in $(basename "$tarball")"
        fi
    done
    # Notices: the leading comment block of a source file, verbatim
    for notice in $notices; do
        path="${notice%%:*}"
        name="${notice#*:}"
        member="$(find_member "$path")"
        if [[ -z "$member" || "$member" == *$'\n'* ]]; then
            err "$formula: $path not found (exactly once) in $(basename "$tarball")"
            continue
        fi
        tar -xOf "$tarball" "$member" \
            | awk 'NR == 1 && $0 !~ /^\/\*/ { exit } { print } /\*\// { exit }' > "$dest/$name"
        if grep -q '\*/' "$dest/$name" && grep -qi 'copyright' "$dest/$name"; then
            echo "  📄 $formula/$name  <- leading comment of $(basename "$tarball"):$member"
        else
            err "$formula: $member does not start with a comment block carrying a copyright notice"
        fi
    done
done < "$WORK/formulas"

### ── MANIFEST.tsv ──
{
    echo "# Bundled file<TAB>component (LICENSES/<component>/). Generated by assets/collect-licenses.sh;"
    echo "# checked by scripts/verify-licenses.sh. Sources of every component: LICENSES/SOURCES.txt"
    cut -f1,2 "$WORK/manifest"
} > "$LICENSES/MANIFEST.tsv"

### ── SOURCES.txt ──
{
    echo "Corresponding source of the binaries in this bundle"
    echo "==================================================="
    echo ""
    echo "Every file in bin/ and lib/ is taken from a Homebrew bottle, which Homebrew builds from the upstream source"
    echo "release below using the Homebrew formula linked for it (the formula lists the build options and any patches)."
    echo "Bundling only rewrites the dylib load paths (install_name_tool), strips local symbols (strip -x) and ad-hoc"
    echo "code-signs the files; no source code is changed. The license texts in LICENSES/<component>/ are copied from"
    echo "the source tarball listed for that component. LICENSES/MANIFEST.tsv maps every bundled file to its component."
    echo ""
    while read -r formula; do
        src="$(awk -F'\t' -v f="$formula" '$1 == f' "$WORK/sources")"
        [[ -n "$src" ]] || continue
        version="$(field "$src" 2)"
        url="$(field "$src" 3)"
        sha256="$(field "$src" 4)"
        license="$(field "$src" 6)"
        formula_url="$(field "$src" 7)"
        echo "[$formula]"
        echo "  version:  $version"
        echo "  license:  ${license:-see LICENSES/$formula/}"
        echo "  source:   $url"
        echo "  sha256:   $sha256"
        echo "  formula:  ${formula_url:-unknown}"
        echo "  licenses: LICENSES/$formula/ ($(find "$LICENSES/$formula" -type f -exec basename {} \; 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//'))"
        echo "  files:    $(awk -F'\t' -v f="$formula" '$2 == f {print $1}' "$WORK/manifest" | tr '\n' ' ' | sed 's/ $//')"
        echo ""
    done < "$WORK/formulas"
} > "$LICENSES/SOURCES.txt"

if [[ "$errors" -ne 0 ]]; then
    echo "❌ License collection failed with $errors error(s)"
    exit 1
fi
echo "✅ Licenses collected for: $(tr '\n' ' ' < "$WORK/formulas")"
