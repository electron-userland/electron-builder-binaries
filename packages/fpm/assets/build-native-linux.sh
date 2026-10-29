#!/usr/bin/env bash
# Builds the native tools of the Linux fpm toolset into <stage>, laid out as they go into the bundle root:
#   bin/xz                      XZ Utils (build-xz.sh)
#   bin/{rpm,rpmbuild}          WITH_RPM=1: the relocatable rpm wrappers from packages/rpm, with the
#   libexec/ lib/ share/        executables, libraries, RPM_CONFIGDIR and magic database they resolve
#                               relative to bin/
#   LICENSES/<component>/       their licenses, and LICENSES/MANIFEST.tsv (paths relative to the bundle root)
#   VERSION.txt                 what was built
# Runs inside the build image (manylinux, see build.sh and native-constants.sh) with the repository at
# $REPO_DIR: rpm is built by packages/rpm/assets/build-linux.sh, whose libraries come from the image's
# packages, so their licenses are collected here, from the same rpm database.
#
# Usage: build-native-linux.sh <stage-dir>
# Env:   WITH_RPM=1|0  also build rpm (default 1)
#        WORK_DIR      scratch directory (default /tmp/fpm-native)
set -euo pipefail

ASSETS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RPM_ASSETS=$(cd "$ASSETS/../../rpm/assets" && pwd)
VERIFY_LICENSES="${VERIFY_LICENSES:-$ASSETS/../../../scripts/verify-licenses.sh}"
# shellcheck source=SCRIPTDIR/../../rpm/assets/constants.sh
source "$RPM_ASSETS/constants.sh"
# shellcheck source=SCRIPTDIR/native-constants.sh
source "$ASSETS/native-constants.sh"

STAGE="${1:?usage: build-native-linux.sh <stage-dir>}"
WORK="${WORK_DIR:-/tmp/fpm-native}"
WITH_RPM="${WITH_RPM:-1}"

die() {
    echo "❌ $*" >&2
    exit 1
}

rm -rf "$STAGE"
mkdir -p "$STAGE/LICENSES" "$WORK"
STAGE=$(cd "$STAGE" && pwd)
MANIFEST="$STAGE/LICENSES/MANIFEST.tsv"
: >"$MANIFEST"

echo "🐧 Native tools for the fpm toolset on $(. /etc/os-release && echo "$PRETTY_NAME") ($(uname -m)), WITH_RPM=$WITH_RPM"
ldd --version | sed -n 1p

# --- rpm ---------------------------------------------------------------------
# rpm_package_license <package> <library>: copies the package's %license files into LICENSES/<package>/
rpm_package_license() {
    local pkg="$1" lib="$2" dest="$STAGE/LICENSES/$1" count=0 lic luah
    [ -d "$dest" ] && return 0
    mkdir -p "$dest"
    while IFS= read -r lic; do
        [ -f "$lic" ] && [ -s "$lic" ] || continue
        cp -L "$lic" "$dest/$(basename "$lic")"
        count=$((count + 1))
    done < <(rpm -qL "$pkg" 2>/dev/null || true)
    if [ "$count" -eq 0 ]; then
        case "$pkg" in
            lua-libs)
                # lua-libs packages no license file; Lua states its (MIT) license at the end of lua.h (lua-devel)
                luah=$(rpm -ql lua-devel 2>/dev/null | grep '/lua\.h$' | sed -n 1p || true)
                [ -n "$luah" ] && [ -f "$luah" ] || die "$lib: lua-libs has no license file and lua.h (lua-devel) is not installed"
                awk '/Copyright \(C\) [0-9-]+ Lua\.org/ {p = 1} p' "$luah" >"$dest/LICENSE"
                grep -q 'Permission is hereby granted' "$dest/LICENSE" || die "$lib: no license text found in $luah"
                echo "  ⚠️ $pkg has no license file; using the license notice from $luah" >&2
                ;;
            *) die "$lib: package $pkg has no license file (rpm -qL $pkg)" ;;
        esac
    fi
    {
        echo "$lib: $(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' "$pkg") from the build image ($(. /etc/os-release && echo "$PRETTY_NAME"))."
        echo "  License: $(rpm -q --qf '%{LICENSE}' "$pkg")"
        echo "  Source package: $(rpm -q --qf '%{SOURCERPM}' "$pkg") (dnf download --source $pkg)"
    } >>"$dest/SOURCE.txt"
    echo "  📄 $pkg: $(cd "$dest" && echo *)"
}

if [ "$WITH_RPM" = "1" ]; then
    RPM_STAGE="$WORK/rpm-stage"
    WORK_DIR="$WORK/rpm" bash "$RPM_ASSETS/build-linux.sh" "$RPM_STAGE"

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
    # every binary rpm added (the image's rpm database still knows where each library came from)
    while IFS= read -r bin; do
        case "$bin" in
            bin/xz) ;;
            libexec/* | lib/librpm* | lib/rpm/*) printf '%s\trpm\n' "$bin" >>"$MANIFEST" ;;
            lib/*/*) die "$bin: no license mapping for this binary" ;;
            lib/*)
                name=$(basename "$bin")
                sys=$(find /usr/lib64 /lib64 /usr/lib /lib -maxdepth 1 -name "$name" 2>/dev/null | sed -n 1p)
                [ -n "$sys" ] || die "$bin: $name is not installed in the build image; cannot find its package"
                pkg=$(rpm -qf --qf '%{NAME}\n' "$sys" | sort -u)
                [ -n "$pkg" ] && [ "$(printf '%s\n' "$pkg" | awk 'END {print NR}')" -eq 1 ] ||
                    die "$bin: expected one package to own $sys, got: $(echo "$pkg" | tr '\n' ' ')"
                rpm_package_license "$pkg" "$bin"
                printf '%s\t%s\n' "$bin" "$pkg" >>"$MANIFEST"
                ;;
            *) die "$bin: no license mapping for this binary" ;;
        esac
    done < <(bash "$VERIFY_LICENSES" --list "$STAGE")
    # share/misc/magic.mgc is libmagic's database, from the same package as libmagic (file-libs)
    grep -q "libmagic" "$MANIFEST" || die "libmagic is not in the rpm bundle; check the magic.mgc license"
fi

# --- xz ----------------------------------------------------------------------
WORK_DIR="$WORK/xz" bash "$ASSETS/build-xz.sh" "$STAGE"

echo "🔍 Checking the glibc floor of the native tools"
bash "$RPM_ASSETS/check-linux-abi.sh" "$STAGE" | tee "$WORK/abi.txt"

echo "🔍 Checking the native tools' licenses"
sort -u -o "$MANIFEST" "$MANIFEST"
bash "$VERIFY_LICENSES" "$STAGE"

{
    echo "native tools (bin/): built on $(. /etc/os-release && echo "$PRETTY_NAME") ($(uname -m)), $(ldd --version | sed -n 1p)"
    echo "xz: ${XZ_VERSION} (sha256 ${XZ_SHA256})"
    if [ "$WITH_RPM" = "1" ]; then
        sed 's/^/rpm bundle: /' "$RPM_STAGE/VERSION.txt"
    fi
    sed 's/^/native /' "$WORK/abi.txt"
} >"$STAGE/VERSION.txt"
cat "$STAGE/VERSION.txt"
echo "✅ Native tools staged at $STAGE"
