#!/usr/bin/env bash
# =============================================================================
# verify-licenses.sh: every binary a toolset bundle ships must carry its license
# =============================================================================
#
#   verify-licenses.sh <bundle-dir>          check the bundle (exit 1 naming every offending path)
#   verify-licenses.sh --list <bundle-dir>   print the binaries found in the bundle, one relative path per line
#
# A binary is any regular file whose first bytes are an executable magic number, whatever its name:
#   ELF                  7f 45 4c 46
#   Mach-O               fe ed fa ce / ce fa ed fe (32-bit), fe ed fa cf / cf fa ed fe (64-bit)
#   Mach-O fat/universal ca fe ba be / ca fe ba bf (and their byte-swapped forms); a Java class file, which
#                        shares ca fe ba be, is told apart by its version field
#   PE / DOS (.exe .dll) 4d 5a ("MZ")
# Symbolic links are not followed: the file they point to is checked where it lives.
#
# Layout inside the bundle:
#   LICENSES/MANIFEST.tsv   "<relative path><TAB><component>" for every binary. A path may contain glob characters
#                           (* ? [...]; * also matches /) to cover many binaries at once. A binary that contains
#                           several components (e.g. statically linked libraries) is listed once per component.
#   LICENSES/<component>/   the component's license files (at least one non-empty file)
#   LICENSES/EXEMPT.tsv     optional: "<relative path or glob><TAB><reason>" for binaries deliberately shipped without
#                           license files while a decision is pending. Every exemption is printed on every run (and
#                           raised as a GitHub Actions warning annotation in CI).
# In both TSV files, blank lines and lines starting with # are ignored, and columns after the second are ignored.
#
# Fails when:
#   - a binary is neither listed in MANIFEST.tsv nor exempted
#   - a listed component has no LICENSES/<component>/ directory with a non-empty file
#   - a MANIFEST.tsv path does not exist in the bundle (a glob: matches no binary)
#   - a MANIFEST.tsv / EXEMPT.tsv line is malformed (missing column, absolute or ../ path, component with a /)
#
# Portable bash: Linux, macOS (bash 3.2) and Git Bash on Windows. Uses only find, sort, awk, od, mktemp.
# =============================================================================
set -euo pipefail

# Byte-wise strings, reads and sorting
export LC_ALL=C

TAB=$(printf '\t')
CR=$(printf '\r')

usage() {
    echo "Usage: $0 [--list] <bundle-dir>" >&2
    exit 2
}

# -----------------------------------------------------------------------------
# Binary detection
# -----------------------------------------------------------------------------

MAGIC_ELF=$'\x7fELF'
MAGIC_MACHO_32=$'\xfe\xed\xfa\xce'
MAGIC_MACHO_32_SWAP=$'\xce\xfa\xed\xfe'
MAGIC_MACHO_64=$'\xfe\xed\xfa\xcf'
MAGIC_MACHO_64_SWAP=$'\xcf\xfa\xed\xfe'
MAGIC_FAT=$'\xca\xfe\xba\xbe'
MAGIC_FAT_SWAP=$'\xbe\xba\xfe\xca'
MAGIC_FAT_64=$'\xca\xfe\xba\xbf'
MAGIC_FAT_64_SWAP=$'\xbf\xba\xfe\xca'

# Read the first 4 bytes with bash itself (no process per file). None of the magic numbers contains a NUL byte, so
# stopping at the first NUL loses nothing. Set to 1 (by the self-check below, or VERIFY_LICENSES_FORCE_OD=1 for tests)
# to read them with od instead.
USE_OD="${VERIFY_LICENSES_FORCE_OD:-0}"

# _hex <file> <offset> <count>: the bytes as lowercase hex, no separators
_hex() {
    od -An -v -tx1 -j "$2" -N "$3" "$1" 2>/dev/null | tr -d ' \n'
}

# _is_fat_macho <file>: tells a fat Mach-O (big-endian ca fe ba be, then nfat_arch) from a Java class file (ca fe ba be,
# then minor and major version, major >= 45)
_is_fat_macho() {
    local h
    h=$(_hex "$1" 4 4)
    case "$h" in
        000000??) [ $((16#${h:6:2})) -gt 0 ] && [ $((16#${h:6:2})) -lt 45 ] ;;
        *) return 1 ;;
    esac
}

# binary_kind <file>: sets KIND to elf, macho, macho-fat or pe, or to "" when the file is not a binary (a variable
# rather than output, so that the common case runs without a subshell)
KIND=""
binary_kind() {
    local f="$1" magic="" h
    KIND=""
    if [ "$USE_OD" = 1 ]; then
        h=$(_hex "$f" 0 4)
        case "$h" in
            7f454c46) KIND=elf ;;
            feedface|cefaedfe|feedfacf|cffaedfe) KIND=macho ;;
            cafebabe) if _is_fat_macho "$f"; then KIND=macho-fat; fi ;;
            bebafeca|cafebabf|bfbafeca) KIND=macho-fat ;;
            4d5a*) KIND=pe ;;
        esac
        return 0
    fi
    IFS= read -r -d '' -n 4 magic < "$f" 2>/dev/null || true
    if [ "$magic" = "$MAGIC_ELF" ]; then
        KIND=elf
    elif [ "$magic" = "$MAGIC_MACHO_32" ] || [ "$magic" = "$MAGIC_MACHO_32_SWAP" ] \
        || [ "$magic" = "$MAGIC_MACHO_64" ] || [ "$magic" = "$MAGIC_MACHO_64_SWAP" ]; then
        KIND=macho
    elif [ "$magic" = "$MAGIC_FAT" ]; then
        if _is_fat_macho "$f"; then KIND=macho-fat; fi
    elif [ "$magic" = "$MAGIC_FAT_SWAP" ] || [ "$magic" = "$MAGIC_FAT_64" ] || [ "$magic" = "$MAGIC_FAT_64_SWAP" ]; then
        KIND=macho-fat
    elif [ "${magic:0:2}" = "MZ" ]; then
        KIND=pe
    fi
    return 0
}

# Make sure this bash reads raw bytes as expected (some builds mangle 0x7f / high bytes); otherwise use od.
_self_check() {
    local dir="$1" expected
    printf '\177ELF\002' > "$dir/elf"
    printf '\317\372\355\376' > "$dir/macho"
    printf '\312\376\272\276\000\000\000\002' > "$dir/macho-fat"
    printf 'MZ\220\000' > "$dir/pe"
    printf '\312\376\272\276\000\000\000\064' > "$dir/none-java"
    printf '#!/bin/sh\n' > "$dir/none-text"
    for expected in elf macho macho-fat pe none-java none-text; do
        binary_kind "$dir/$expected"
        case "$expected" in none-*) [ -z "$KIND" ] ;; *) [ "$KIND" = "$expected" ] ;; esac || return 1
    done
}

# -----------------------------------------------------------------------------
# TSV parsing
# -----------------------------------------------------------------------------

ERRORS=0
# error <message>: one offending item; printed in the summary
error() {
    printf '%s\n' "$1" >> "$WORK/errors"
    ERRORS=$((ERRORS + 1))
}

# _has_glob <string>
_has_glob() {
    case "$1" in *'*'*|*'?'*|*'['*) return 0 ;; esac
    return 1
}

# _bad_path <path>: absolute or escaping the bundle
_bad_path() {
    case "/$1/" in
        //*|*/../*) return 0 ;;
    esac
    case "$1" in [A-Za-z]:*|\\*) return 0 ;; esac
    return 1
}

# read_tsv <file> <output>: writes "<line number><TAB><col1><TAB><col2>" for every non-comment line, normalizing
# CRLF and a leading ./ in the first column
read_tsv() {
    local file="$1" out="$2" n=0 line col1 col2 rest
    : > "$out"
    [ -f "$file" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        n=$((n + 1))
        line="${line%"$CR"}"
        case "$line" in ''|'#'*) continue ;; esac
        IFS="$TAB" read -r col1 col2 rest <<< "$line" || true
        while [ "${col1#./}" != "$col1" ]; do col1="${col1#./}"; done
        printf '%s\t%s\t%s\n' "$n" "$col1" "$col2" >> "$out"
    done < "$file"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

MODE=verify
if [ "${1:-}" = "--list" ]; then
    MODE=list
    shift
fi
[ $# -eq 1 ] || usage
[ -d "$1" ] || { echo "❌ Not a directory: $1" >&2; exit 2; }
ROOT=$(cd "$1" && pwd)

WORK=$(mktemp -d "${TMPDIR:-/tmp}/verify-licenses.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
: > "$WORK/errors"

mkdir "$WORK/self-check"
if [ "$USE_OD" != 1 ] && ! _self_check "$WORK/self-check"; then
    echo "ℹ️  This bash does not read raw bytes reliably; detecting binaries with od (slower)" >&2
    USE_OD=1
fi
if [ "$USE_OD" = 1 ] && ! _self_check "$WORK/self-check"; then
    echo "❌ Cannot detect binaries on this system: od does not read the magic numbers as expected" >&2
    exit 2
fi

# Every binary in the bundle: "<relative path>" (sorted), and "<relative path><TAB><kind>"
: > "$WORK/binaries.tsv"
while IFS= read -r -d '' file; do
    binary_kind "$file"
    [ -n "$KIND" ] || continue
    printf '%s\t%s\n' "${file#"$ROOT"/}" "$KIND" >> "$WORK/binaries.tsv"
done < <(find "$ROOT" -type f -print0)
sort -o "$WORK/binaries.tsv" "$WORK/binaries.tsv"
cut -f1 "$WORK/binaries.tsv" > "$WORK/binaries"
BINARY_COUNT=$(awk 'END {print NR}' "$WORK/binaries")

if [ "$MODE" = list ]; then
    cat "$WORK/binaries"
    exit 0
fi

echo "🔍 Checking the licenses of the binaries in $ROOT"
LICENSES="$ROOT/LICENSES"
MANIFEST="$LICENSES/MANIFEST.tsv"
EXEMPT="$LICENSES/EXEMPT.tsv"

if [ ! -f "$MANIFEST" ] && [ "$BINARY_COUNT" -gt 0 ]; then
    error "LICENSES/MANIFEST.tsv is missing ($BINARY_COUNT binaries need a license entry)"
fi

# --- MANIFEST.tsv: validate lines, split exact paths from globs, check paths exist ---
read_tsv "$MANIFEST" "$WORK/manifest.raw"
: > "$WORK/manifest.exact"
: > "$WORK/manifest.globs"
: > "$WORK/components"
while IFS="$TAB" read -r n path component; do
    where="LICENSES/MANIFEST.tsv:$n"
    if [ -z "$path" ] || [ -z "$component" ]; then
        error "$where: expected \"<relative path><TAB><component>\""
        continue
    fi
    if _bad_path "$path"; then
        error "$where: $path: the path must be relative to the bundle root, without .."
        continue
    fi
    case "$component" in
        .|..|*/*|*\\*) error "$where: $component: not a valid component (directory) name"; continue ;;
    esac
    printf '%s\n' "$component" >> "$WORK/components"
    if _has_glob "$path"; then
        printf '%s\t%s\n' "$path" "$component" >> "$WORK/manifest.globs"
    else
        printf '%s\n' "$path" >> "$WORK/manifest.exact"
        if [ ! -e "$ROOT/$path" ] && [ ! -L "$ROOT/$path" ]; then
            error "$path: listed in LICENSES/MANIFEST.tsv ($component) but not in the bundle"
        fi
    fi
done < "$WORK/manifest.raw"

# Glob entries must match at least one binary
while IFS="$TAB" read -r pattern component; do
    matched=0
    while IFS= read -r bin; do
        # shellcheck disable=SC2053 # $pattern is a glob
        if [[ $bin == $pattern ]]; then matched=1; break; fi
    done < "$WORK/binaries"
    [ "$matched" = 1 ] || error "$pattern: listed in LICENSES/MANIFEST.tsv ($component) but matches no binary in the bundle"
done < "$WORK/manifest.globs"

# --- Every listed component has license files ---
sort -u -o "$WORK/components" "$WORK/components"
while IFS= read -r component; do
    if [ ! -d "$LICENSES/$component" ]; then
        error "LICENSES/$component/: missing (component $component is listed in LICENSES/MANIFEST.tsv)"
    elif [ -z "$(find "$LICENSES/$component" -type f -size +0 | head -n 1)" ]; then
        error "LICENSES/$component/: has no non-empty license file"
    fi
done < "$WORK/components"

# --- Binaries not covered by an exact MANIFEST.tsv path or glob ---
# (FILENAME rather than NR == FNR: the first file may be empty)
awk 'FILENAME == ARGV[1] {listed[$0] = 1; next} !($0 in listed)' "$WORK/manifest.exact" "$WORK/binaries" > "$WORK/candidates"
: > "$WORK/unlisted"
while IFS= read -r bin; do
    covered=0
    while IFS="$TAB" read -r pattern component; do
        # shellcheck disable=SC2053 # $pattern is a glob
        if [[ $bin == $pattern ]]; then covered=1; break; fi
    done < "$WORK/manifest.globs"
    [ "$covered" = 1 ] || printf '%s\n' "$bin" >> "$WORK/unlisted"
done < "$WORK/candidates"

# --- EXEMPT.tsv: print every exemption loudly; unlisted binaries it covers are not errors ---
read_tsv "$EXEMPT" "$WORK/exempt.raw"
: > "$WORK/exempted"
EXEMPT_COUNT=0
while IFS="$TAB" read -r n pattern reason; do
    where="LICENSES/EXEMPT.tsv:$n"
    if [ -z "$pattern" ] || [ -z "$reason" ]; then
        error "$where: expected \"<relative path or glob><TAB><reason>\""
        continue
    fi
    if _bad_path "$pattern"; then
        error "$where: $pattern: the path must be relative to the bundle root, without .."
        continue
    fi
    : > "$WORK/exempt.matches"
    while IFS= read -r bin; do
        # shellcheck disable=SC2053 # $pattern is a path or a glob
        if [[ $bin == $pattern ]]; then printf '%s\n' "$bin" >> "$WORK/exempt.matches"; fi
    done < "$WORK/unlisted"
    cat "$WORK/exempt.matches" >> "$WORK/exempted"
    EXEMPT_COUNT=$((EXEMPT_COUNT + 1))
    echo ""
    echo "⚠️  LICENSE EXEMPTION: $pattern"
    echo "    Reason: $reason"
    if [ -s "$WORK/exempt.matches" ]; then
        echo "    Binaries shipped WITHOUT license files under this exemption:"
        sed 's/^/      - /' "$WORK/exempt.matches"
    else
        echo "    Matches no unlisted binary: remove it from LICENSES/EXEMPT.tsv if it is no longer needed"
    fi
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
        msg="$pattern: $reason ($(awk 'END {print NR}' "$WORK/exempt.matches") binaries without license files)"
        msg=$(printf '%s' "$msg" | sed -e 's/%/%25/g')
        echo "::warning title=License exemption::$msg"
    fi
done < "$WORK/exempt.raw"
[ "$EXEMPT_COUNT" -eq 0 ] || echo ""

# "<path><TAB><kind>" for every binary neither listed nor exempted
awk -F'\t' 'FILENAME == ARGV[1] {exempt[$0] = 1; next}
    FILENAME == ARGV[2] {unlisted[$0] = 1; next}
    ($1 in unlisted) && !($1 in exempt)' "$WORK/exempted" "$WORK/unlisted" "$WORK/binaries.tsv" > "$WORK/unlicensed"
while IFS="$TAB" read -r bin kind; do
    error "$bin: $kind binary not listed in LICENSES/MANIFEST.tsv"
done < "$WORK/unlicensed"

# --- Summary ---
EXEMPTED_BINARIES=$(sort -u "$WORK/exempted" | awk 'END {print NR}')
if [ "$ERRORS" -gt 0 ]; then
    echo "❌ License check failed ($ERRORS problem(s); $BINARY_COUNT binaries, $EXEMPTED_BINARIES exempted):"
    sed 's/^/   - /' "$WORK/errors"
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
        echo "::error title=License check failed::$ERRORS problem(s) in $ROOT; see the log for every offending path"
    fi
    exit 1
fi
echo "✓ All $BINARY_COUNT binaries have license files ($EXEMPTED_BINARIES exempted by LICENSES/EXEMPT.tsv)"
