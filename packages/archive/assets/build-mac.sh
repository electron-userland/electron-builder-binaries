#!/usr/bin/env bash
# Builds the macOS archive toolset for the runner's architecture into <stage>, from sources fetch-sources.sh already
# downloaded and verified:
#   bin/{xz,lzip,tar,gtar,ar,gar,bsdtar}   build-tools.sh (only /usr/lib system libraries, MACOS_MIN)
#   bin/{rpm,rpmbuild} libexec/ lib/ share/ arm64 only: rpm/build-mac.sh (the rpm@1.0.0 build). Its Homebrew
#                                          dylibs are copied into lib/ with @rpath install names, and their licenses
#                                          and source pointers are collected here from the formulae
#   LICENSES/  VERSION.txt
#
# Usage: build-mac.sh <sources-dir> <stage-dir>
# Env:   WITH_RPM=1|0  build rpm (default: 1 on arm64, 0 otherwise; Intel macOS ships no rpm)
#        WORK_DIR      scratch directory (default /tmp/archive-build)
set -euo pipefail

[ "$(uname -s)" = "Darwin" ] || { echo "❌ Must be run on macOS"; exit 1; }

ASSETS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=SCRIPTDIR/constants.sh
source "$ASSETS/constants.sh"
# shellcheck source=SCRIPTDIR/licenses.sh
source "$ASSETS/licenses.sh"
VERIFY_LICENSES="$ASSETS/../../../scripts/verify-licenses.sh"

SOURCES=$(cd "${1:?usage: build-mac.sh <sources-dir> <stage-dir>}" && pwd)
STAGE="${2:?usage: build-mac.sh <sources-dir> <stage-dir>}"
WORK="${WORK_DIR:-/tmp/archive-build}"
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then WITH_RPM="${WITH_RPM:-1}"; else WITH_RPM="${WITH_RPM:-0}"; fi

rm -rf "$STAGE" "$WORK"
mkdir -p "$STAGE/LICENSES" "$WORK"
STAGE=$(cd "$STAGE" && pwd)
echo "🍎 archive toolset on macOS $(sw_vers -productVersion) ($ARCH), Xcode $(xcodebuild -version | awk 'NR == 1 {print $2}'), WITH_RPM=$WITH_RPM"

# --- xz, lzip, GNU tar, GNU ar, bsdtar -------------------------------------------------------------------------
WORK_DIR="$WORK/tools" bash "$ASSETS/build-tools.sh" "$SOURCES" "$STAGE"

# --- rpm -------------------------------------------------------------------------------------------------------
# brew_formula_of <dylib name>: the formula whose keg the dylib was copied from
brew_formula_of() {
    local name="$1" candidate real formulae=""
    # (no case statement inside $(...): bash 3.2 cannot parse it)
    for candidate in "$BREW_PREFIX"/opt/*/lib/"$name"; do
        [ -e "$candidate" ] || continue
        real=$(grealpath "$candidate")
        if [[ "$real" == "$BREW_PREFIX"/Cellar/* ]]; then
            real="${real#"$BREW_PREFIX"/Cellar/}"
            formulae="$formulae${real%%/*}"$'\n'
        fi
    done
    formulae=$(printf '%s' "$formulae" | sort -u)
    [ -n "$formulae" ] && [ "$(printf '%s\n' "$formulae" | awk 'END {print NR}')" -eq 1 ] ||
        die "$name: expected one Homebrew formula to provide it, got: $(echo "$formulae" | tr '\n' ' ')"
    echo "$formulae"
}

# brew_license <formula> <library>: the keg's license files into LICENSES/<formula>/, and the formula's pinned
# upstream source (URL and sha256 from `brew info`) into SOURCES.txt
brew_license() {
    local formula="$1" lib="$2" prefix dest="$STAGE/LICENSES/$1" count=0 f luah info
    [ -d "$dest" ] && return 0
    prefix=$(brew --prefix "$formula")
    mkdir -p "$dest"
    # Homebrew installs a formula's top-level license files into the keg root
    shopt -s nullglob nocaseglob
    for f in "$prefix"/LICENSE* "$prefix"/LICENCE* "$prefix"/COPYING* "$prefix"/COPYRIGHT* "$prefix"/NOTICE*; do
        [ -f "$f" ] && [ -s "$f" ] || continue
        cp -L "$f" "$dest/"
        count=$((count + 1))
    done
    shopt -u nullglob nocaseglob
    if [ "$count" -eq 0 ]; then
        case "$formula" in
            lua)
                # Lua's tarball has no license file; it states its (MIT) license at the end of lua.h
                luah=$(find "$prefix/include" -name lua.h | sed -n 1p)
                [ -n "$luah" ] || die "$lib: no license file and no lua.h in $prefix"
                awk '/Copyright \(C\) [0-9-]+ Lua\.org/ {p = 1} p' "$luah" >"$dest/LICENSE"
                grep -q 'Permission is hereby granted' "$dest/LICENSE" || die "$lib: no license text found in $luah"
                echo "  ⚠️ $formula has no license file; using the license notice from $luah" >&2
                ;;
            *) die "$lib: no license file in the Homebrew keg $prefix ($formula)" ;;
        esac
    fi
    info=$(brew info --json=v2 "$formula")
    add_source_block "$formula" "$(brew list --versions "$formula" | awk '{print $NF}')" \
        "$(jq -r '.formulae[0].license // "see LICENSES" | if type == "string" then . else tojson end' <<<"$info")" \
        "$(jq -r '.formulae[0].urls.stable.url' <<<"$info")" "$(jq -r '.formulae[0].urls.stable.checksum // empty' <<<"$info")" \
        "Dynamic library taken from the Homebrew bottle (formula: https://github.com/Homebrew/homebrew-core/blob/$(jq -r '.formulae[0].tap_git_head // "HEAD"' <<<"$info")/$(jq -r '.formulae[0].ruby_source_path // empty' <<<"$info")) for rpm; install names rewritten to @rpath, stripped, ad-hoc signed."
    echo "  📄 LICENSES/$formula: $(cd "$dest" && ls | tr '\n' ' ')"
}

RPM_STAGE="$WORK/rpm-stage"
if [ "$WITH_RPM" = "1" ]; then
    [ "$ARCH" = "arm64" ] || die "rpm is only built for macOS arm64"
    command -v jq >/dev/null || die "jq is needed"
    RPM_TARBALL=$(source_tarball RPM "$SOURCES") WORK_DIR="$WORK/rpm" bash "$ASSETS/rpm/build-mac.sh" "$RPM_STAGE"
    BREW_PREFIX="$(brew --prefix)"

    echo "📄 Mapping the rpm bundle's binaries to their licenses"
    [ -s "$RPM_STAGE/LICENSES/COPYING.rpm" ] || die "rpm bundle has no LICENSES/COPYING.rpm"
    mkdir -p "$STAGE/LICENSES/rpm"
    cp "$RPM_STAGE/LICENSES/COPYING.rpm" "$STAGE/LICENSES/rpm/COPYING"
    add_source_block rpm "$RPM_VERSION" "$RPM_LICENSE" "$RPM_URL" "$RPM_SHA256" \
        "bin/rpm and bin/rpmbuild (wrappers), libexec/, lib/librpm*, lib/rpm/: built by rpm/build-mac.sh with patches: $(cd "$ASSETS/rpm/patches" && ls | tr '\n' ' ')"
    while IFS= read -r bin; do
        case "$bin" in
            libexec/* | lib/librpm* | lib/rpm/*) add_binaries rpm "$bin" ;;
            lib/*/*) die "$bin: no license mapping for this binary" ;;
            lib/*.dylib)
                formula=$(brew_formula_of "$(basename "$bin")")
                brew_license "$formula" "$bin"
                add_binaries "$formula" "$bin"
                ;;
            *) die "$bin: no license mapping for this binary" ;;
        esac
    done < <(bash "$VERIFY_LICENSES" --list "$RPM_STAGE")
    grep -q libmagic "$STAGE/LICENSES/MANIFEST.tsv" || die "libmagic is not in the rpm bundle; check the magic.mgc license"

    echo "📁 Adding rpm (bin/, libexec/, lib/, share/)"
    for entry in bin libexec lib share; do
        [ -d "$RPM_STAGE/$entry" ] || die "rpm bundle has no $entry/"
        mkdir -p "$STAGE/$entry"
        for f in "$RPM_STAGE/$entry"/*; do
            [ ! -e "$STAGE/$entry/$(basename "$f")" ] || die "$entry/$(basename "$f") is in both the rpm bundle and the tools"
            cp -a "$f" "$STAGE/$entry/"
        done
    done
fi

finish_manifest

# --- checks and VERSION.txt --------------------------------------------------------------------------------------
verify_args=(--bundle-dir "$STAGE")
if [ "$WITH_RPM" = "1" ]; then verify_args+=(--expect-rpm); fi
bash "$ASSETS/verify-bundle.sh" "${verify_args[@]}" | tee "$WORK/verify.txt"

{
    echo "archive toolset: darwin $ARCH, built on macOS $(sw_vers -productVersion), MACOSX_DEPLOYMENT_TARGET=$MACOS_MIN"
    echo "compiler: $(clang --version | sed -n 1p)"
    for c in XZ LZIP TAR BINUTILS LIBARCHIVE; do
        echo "$(echo "$c" | tr '[:upper:]' '[:lower:]'): $(component_var "$c" VERSION) (sha256 $(component_var "$c" SHA256))"
    done
    cat "$WORK/tools/versions.txt"
    if [ "$WITH_RPM" = "1" ]; then sed 's/^/rpm bundle: /' "$RPM_STAGE/VERSION.txt"; fi
    grep -E '^ *max-' "$WORK/verify.txt" | sed 's/^ *//' || true
} >"$STAGE/VERSION.txt"
cat "$STAGE/VERSION.txt"
du -sh "$STAGE"
echo "✅ archive toolset staged at $STAGE"
