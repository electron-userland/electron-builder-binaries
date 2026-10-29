#!/usr/bin/env bash
# Builds the native tools of the macOS fpm toolset into <stage>, laid out as they go into the bundle root
# (see build-native-linux.sh): bin/xz on both architectures, plus rpm (bin/{rpm,rpmbuild}, libexec/, lib/,
# share/) on arm64 only, built by packages/rpm/assets/build-mac.sh. Intel macOS ships no rpm.
# The licenses of the Homebrew libraries rpm bundles are collected from the formulae they were copied from.
#
# Usage: build-native-mac.sh <stage-dir>
# Env:   WITH_RPM=1|0  build rpm (default: 1 on arm64, 0 otherwise)
#        WORK_DIR      scratch directory (default /tmp/fpm-native)
set -euo pipefail

[ "$(uname -s)" = "Darwin" ] || { echo "❌ Must be run on macOS"; exit 1; }

ASSETS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RPM_ASSETS=$(cd "$ASSETS/../../rpm/assets" && pwd)
VERIFY_LICENSES="${VERIFY_LICENSES:-$ASSETS/../../../scripts/verify-licenses.sh}"
# shellcheck source=SCRIPTDIR/../../rpm/assets/constants.sh
source "$RPM_ASSETS/constants.sh"
# shellcheck source=SCRIPTDIR/native-constants.sh
source "$ASSETS/native-constants.sh"

STAGE="${1:?usage: build-native-mac.sh <stage-dir>}"
WORK="${WORK_DIR:-/tmp/fpm-native}"
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then WITH_RPM="${WITH_RPM:-1}"; else WITH_RPM="${WITH_RPM:-0}"; fi

die() {
    echo "❌ $*" >&2
    exit 1
}

rm -rf "$STAGE"
mkdir -p "$STAGE/LICENSES" "$WORK"
STAGE=$(cd "$STAGE" && pwd)
MANIFEST="$STAGE/LICENSES/MANIFEST.tsv"
: >"$MANIFEST"
echo "🍎 Native tools for the fpm toolset on macOS $(sw_vers -productVersion) ($ARCH), WITH_RPM=$WITH_RPM"

# --- rpm ---------------------------------------------------------------------
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

# brew_license <formula> <library>: the keg's license files into LICENSES/<formula>/
brew_license() {
    local formula="$1" lib="$2" prefix dest="$STAGE/LICENSES/$1" count=0 f luah
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
    {
        echo "$lib: Homebrew formula $(brew list --versions "$formula" | head -n 1)."
        echo "  Source: run \`brew info $formula\` for the source URL"
    } >>"$dest/SOURCE.txt"
    echo "  📄 $formula: $(cd "$dest" && echo *)"
}

if [ "$WITH_RPM" = "1" ]; then
    [ "$ARCH" = "arm64" ] || die "rpm is only built for macOS arm64"
    RPM_STAGE="$WORK/rpm-stage"
    # install_name_tool from Xcode < 26 rejects Homebrew's ld_prime dylibs (see build-rpm.yaml); pick
    # Xcode 26 for the rpm build only, so the Ruby build keeps the runner's default toolchain.
    XCODE_APP=$(find /Applications -maxdepth 1 -name 'Xcode_26*.app' 2>/dev/null | sort -V | tail -n 1)
    if [ -n "$XCODE_APP" ]; then
        echo "🛠️  rpm build uses $XCODE_APP"
        DEVELOPER_DIR="$XCODE_APP/Contents/Developer" WORK_DIR="$WORK/rpm" bash "$RPM_ASSETS/build-mac.sh" "$RPM_STAGE"
    else
        WORK_DIR="$WORK/rpm" bash "$RPM_ASSETS/build-mac.sh" "$RPM_STAGE"
    fi
    BREW_PREFIX="$(brew --prefix)"

    echo "📁 Adding rpm to the native tools"
    for entry in bin libexec lib share; do
        [ -d "$RPM_STAGE/$entry" ] || die "rpm bundle has no $entry/"
        mkdir -p "$STAGE/$entry"
        cp -a "$RPM_STAGE/$entry/." "$STAGE/$entry/"
    done

    echo "📄 Collecting the rpm bundle's licenses"
    mkdir -p "$STAGE/LICENSES/rpm"
    [ -s "$RPM_STAGE/LICENSES/COPYING.rpm" ] || die "rpm bundle has no LICENSES/COPYING.rpm"
    cp "$RPM_STAGE/LICENSES/COPYING.rpm" "$STAGE/LICENSES/rpm/COPYING"
    {
        echo "bin/rpm, bin/rpmbuild, libexec/, lib/librpm*, lib/rpm/: rpm ${RPM_VERSION}, built from the upstream release tarball by packages/rpm."
        echo "  Source: ${RPM_URL}"
        echo "  sha256: ${RPM_SHA256}"
    } >"$STAGE/LICENSES/rpm/SOURCE.txt"
    while IFS= read -r bin; do
        case "$bin" in
            bin/xz) ;;
            libexec/* | lib/librpm* | lib/rpm/*) printf '%s\trpm\n' "$bin" >>"$MANIFEST" ;;
            lib/*/*) die "$bin: no license mapping for this binary" ;;
            lib/*.dylib)
                formula=$(brew_formula_of "$(basename "$bin")")
                brew_license "$formula" "$bin"
                printf '%s\t%s\n' "$bin" "$formula" >>"$MANIFEST"
                ;;
            *) die "$bin: no license mapping for this binary" ;;
        esac
    done < <(bash "$VERIFY_LICENSES" --list "$STAGE")
    grep -q "libmagic" "$MANIFEST" || die "libmagic is not in the rpm bundle; check the magic.mgc license"
fi

# --- xz ----------------------------------------------------------------------
WORK_DIR="$WORK/xz" bash "$ASSETS/build-xz.sh" "$STAGE"

echo "🔍 Checking the native tools' licenses"
sort -u -o "$MANIFEST" "$MANIFEST"
bash "$VERIFY_LICENSES" "$STAGE"

{
    echo "native tools (bin/): built on macOS $(sw_vers -productVersion) ($ARCH), MACOSX_DEPLOYMENT_TARGET=$MACOS_MIN"
    echo "xz: ${XZ_VERSION} (sha256 ${XZ_SHA256})"
    if [ "$WITH_RPM" = "1" ]; then
        sed 's/^/rpm bundle: /' "$RPM_STAGE/VERSION.txt"
    fi
} >"$STAGE/VERSION.txt"
cat "$STAGE/VERSION.txt"
echo "✅ Native tools staged at $STAGE"
