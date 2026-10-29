#!/usr/bin/env bash
# Static checks of a (staged or extracted) archive toolset. Runs at the end of the build and again on the extracted
# archive in every test job. Fails unless:
#   - bin/ holds exactly the expected tools (ARCHIVE_BINS, plus RPM_BINS with --expect-rpm), all executable
#   - with --expect-rpm, the files rpm's wrappers resolve relative to bin/ exist (libexec/, lib/rpm/, share/misc/)
#   - scripts/verify-licenses.sh passes (every binary in LICENSES/MANIFEST.tsv, every component has license texts),
#     there is no LICENSES/EXEMPT.tsv, and LICENSES/SOURCES.txt has a block with a source for every component
#   - Linux: every ELF resolves its libraries from the bundle or the C library (no LD_LIBRARY_PATH), the tools in bin/
#     need only the C library, and no ELF needs a newer glibc/libstdc++ than MAX_GLIBC/MAX_GLIBCXX/MAX_CXXABI
#   - macOS: every Mach-O loads only /usr/lib or /System libraries or bundle libraries through @rpath/@loader_path,
#     has no LC_RPATH outside the bundle, needs at most MACOS_MIN and has a valid (ad-hoc) signature
#
# Usage: verify-bundle.sh --bundle-dir <dir> [--expect-rpm]
set -euo pipefail

ASSETS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=SCRIPTDIR/constants.sh
source "$ASSETS/constants.sh"
GUARD="$ASSETS/../../../scripts/verify-licenses.sh"

BUNDLE="" EXPECT_RPM=0
while [ $# -gt 0 ]; do
    case "$1" in
        --bundle-dir) BUNDLE="$2"; shift 2 ;;
        --expect-rpm) EXPECT_RPM=1; shift ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done
[ -n "$BUNDLE" ] && [ -d "$BUNDLE/bin" ] || { echo "Usage: $0 --bundle-dir <dir> [--expect-rpm]" >&2; exit 2; }
BUNDLE=$(cd "$BUNDLE" && pwd -P)
OS=$(uname -s)

errors=0
err() { echo "  ❌ $*"; errors=$((errors + 1)); }
ok() { echo "  ✅ $*"; }

echo "🔎 Verifying $BUNDLE"

# --- bin/ --------------------------------------------------------------------------------------------------------
expected="$ARCHIVE_BINS"
if [ "$EXPECT_RPM" = "1" ]; then expected="$expected $RPM_BINS"; fi
# shellcheck disable=SC2086 # word splitting of the tool lists
expected=$(printf '%s\n' $expected | sort | tr '\n' ' ')
actual=$(cd "$BUNDLE/bin" && ls | sort | tr '\n' ' ')
if [ "$actual" = "$expected" ]; then ok "bin/: $actual"; else err "bin/ holds '$actual', expected '$expected'"; fi
for f in "$BUNDLE"/bin/*; do
    if [ -L "$f" ]; then err "bin/$(basename "$f") is a symlink (archives must not depend on them)"; fi
    [ -x "$f" ] || err "bin/$(basename "$f") is not executable"
done
if [ "$EXPECT_RPM" = "1" ]; then
    for f in libexec/rpm libexec/rpmbuild lib/rpm/macros lib/rpm/rpmrc lib/rpm/electron-builder/macros share/misc/magic.mgc; do
        [ -e "$BUNDLE/$f" ] || err "$f is missing (rpm's wrappers resolve it relative to bin/)"
    done
else
    for f in libexec lib share; do
        [ ! -e "$BUNDLE/$f" ] || err "$f/ exists, but this bundle ships no rpm"
    done
fi

# --- licenses ----------------------------------------------------------------------------------------------------
if bash "$GUARD" "$BUNDLE"; then ok "scripts/verify-licenses.sh"; else err "scripts/verify-licenses.sh failed (see above)"; fi
[ ! -e "$BUNDLE/LICENSES/EXEMPT.tsv" ] || err "LICENSES/EXEMPT.tsv: every binary of this toolset has a license; remove it"
if [ -f "$BUNDLE/LICENSES/SOURCES.txt" ]; then
    for component in $(grep -v '^#' "$BUNDLE/LICENSES/MANIFEST.tsv" | cut -f2 | sort -u); do
        block=$(awk -v h="[$component]" '$0 == h { f = 1; next } /^\[/ { f = 0 } f' "$BUNDLE/LICENSES/SOURCES.txt")
        if echo "$block" | grep -E '^ *source: +[^ ]' >/dev/null; then
            :
        else
            err "LICENSES/SOURCES.txt: no [$component] block with a source"
        fi
    done
    ok "LICENSES/SOURCES.txt names the source of every component"
else
    err "LICENSES/SOURCES.txt is missing (corresponding-source pointer for the GPL components)"
fi

# --- linkage -----------------------------------------------------------------------------------------------------
if [ "$OS" = "Linux" ]; then
    # (ELF files: the license guard's binary detector)
    while IFS= read -r rel; do
        f="$BUNDLE/$rel"
        out=$(env -u LD_LIBRARY_PATH ldd "$f" 2>&1 || true)
        if echo "$out" | grep 'not found' >/dev/null; then err "$rel: unresolved libraries: $(echo "$out" | grep 'not found' | tr '\n' ' ')"; fi
        case "$rel" in
            bin/*)
                extra=$(echo "$out" | awk '{print $1}' | grep -vE '^(linux-vdso\.so|linux-gate\.so|/lib.*/ld-linux|ld-linux|libc\.so|libm\.so|libdl\.so|libpthread\.so|librt\.so|statically|not)' || true)
                [ -z "$extra" ] || err "$rel needs more than the C library: $(echo "$extra" | tr '\n' ' ')"
                ;;
            *)
                bad=$(echo "$out" | awk '/=> \// {print $3}' | grep -vE "^($BUNDLE/|/lib|/usr/lib)" || true)
                [ -z "$bad" ] || err "$rel loads libraries from outside the bundle and the system: $bad"
                ;;
        esac
    done < <(bash "$GUARD" --list "$BUNDLE")
    if abi=$(bash "$ASSETS/rpm/check-linux-abi.sh" "$BUNDLE" 2>&1); then
        echo "$abi" | sed 's/^/  /'
        ok "glibc/libstdc++ ceiling (MAX_GLIBC=$MAX_GLIBC)"
    else
        echo "$abi" | sed 's/^/  /'
        err "an ELF exceeds the glibc/libstdc++ ceiling"
    fi
else
    max_minos=""
    while IFS= read -r rel; do
        f="$BUNDLE/$rel"
        dir=$(dirname "$f")
        rpaths=$(otool -l "$f" | awk '/cmd LC_RPATH$/ { r = 1; next } r && $1 == "path" { print $2; r = 0 }')
        for rp in $rpaths; do
            case "$rp" in
                @loader_path*) [ -d "${rp/#@loader_path/$dir}" ] || err "$rel: LC_RPATH $rp does not exist in the bundle" ;;
                *) err "$rel: LC_RPATH $rp points outside the bundle" ;;
            esac
        done
        while IFS= read -r dep; do
            case "$dep" in
                /usr/lib/* | /System/*) ;;
                @loader_path/*) [ -e "$dir/${dep#@loader_path/}" ] || err "$rel: $dep does not resolve" ;;
                @rpath/*)
                    found=0
                    for rp in $rpaths; do
                        if [ -e "${rp/#@loader_path/$dir}/${dep#@rpath/}" ]; then found=1; fi
                    done
                    [ "$found" = "1" ] || err "$rel: $dep does not resolve inside the bundle"
                    ;;
                *) err "$rel loads $dep" ;;
            esac
        done < <(otool -L "$f" | tail -n +2 | awk '{print $1}' | grep -vx "$(otool -D "$f" | tail -n +2 | sed -n 1p)" || true)
        case "$rel" in
            bin/*)
                if otool -L "$f" | tail -n +2 | awk '{print $1}' | grep -v -e '^/usr/lib/' -e '^/System/' >/dev/null; then
                    err "$rel needs more than macOS system libraries"
                fi
                ;;
        esac
        minos=$(otool -l "$f" | awk '/LC_BUILD_VERSION/{b=1} b&&/minos/{print $2; b=0}' | sort -V | tail -1)
        if [ -n "$minos" ] && [ "$(printf '%s\n%s\n' "$minos" "$MACOS_MIN" | sort -V | tail -1)" != "$MACOS_MIN" ]; then
            err "$rel requires macOS $minos > $MACOS_MIN"
        fi
        max_minos=$(printf '%s\n%s\n' "$minos" "$max_minos" | sort -V | tail -1)
        codesign --verify "$f" 2>/dev/null || err "$rel: invalid code signature"
        if strings "$f" | grep -E '^(/opt/homebrew|/usr/local)/' >/dev/null; then
            echo "  ⚠️  $rel mentions a Homebrew path: $(strings "$f" | grep -E '^(/opt/homebrew|/usr/local)/' | sed -n 1p)"
        fi
    done < <(bash "$GUARD" --list "$BUNDLE")
    echo "max-minos: $max_minos"
    ok "Mach-O linkage, minos <= $MACOS_MIN, signatures"
fi

if [ "$errors" -ne 0 ]; then
    echo "❌ $errors problem(s) in $BUNDLE"
    exit 1
fi
echo "✅ $BUNDLE verified"
