#!/usr/bin/env bash
# Builds the Linux archive toolset into <stage>. Runs inside the build image (manylinux, see ../build.sh) with the
# repository mounted, from sources fetch-sources.sh already downloaded and verified:
#   bin/{xz,lzip,tar,gtar,ar,gar,bsdtar}   build-tools.sh
#   bin/{rpm,rpmbuild} libexec/ lib/ share/ WITH_RPM=1: rpm/build-linux.sh (the rpm@1.0.0 build); the libraries it
#                                          bundles come from the image's packages, whose licenses are collected here
#   LICENSES/  VERSION.txt
#
# Usage: build-linux.sh <sources-dir> <stage-dir>
# Env:   WITH_RPM=1|0  also build rpm (default 1)
#        WORK_DIR      scratch directory (default /tmp/archive-build)
set -euo pipefail

ASSETS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=SCRIPTDIR/constants.sh
source "$ASSETS/constants.sh"
# shellcheck source=SCRIPTDIR/licenses.sh
source "$ASSETS/licenses.sh"
VERIFY_LICENSES="$ASSETS/../../../scripts/verify-licenses.sh"

SOURCES=$(cd "${1:?usage: build-linux.sh <sources-dir> <stage-dir>}" && pwd)
STAGE="${2:?usage: build-linux.sh <sources-dir> <stage-dir>}"
WORK="${WORK_DIR:-/tmp/archive-build}"
WITH_RPM="${WITH_RPM:-1}"

rm -rf "$STAGE" "$WORK"
mkdir -p "$STAGE/LICENSES" "$WORK"
STAGE=$(cd "$STAGE" && pwd)

echo "🐧 archive toolset on $(. /etc/os-release && echo "$PRETTY_NAME") ($(uname -m)), WITH_RPM=$WITH_RPM"
ldd --version | sed -n 1p

# --- xz, lzip, GNU tar, GNU ar, bsdtar -------------------------------------------------------------------------
WORK_DIR="$WORK/tools" bash "$ASSETS/build-tools.sh" "$SOURCES" "$STAGE"

# --- rpm -------------------------------------------------------------------------------------------------------
# rpm_package_license <package> <library>: the package's %license files into LICENSES/<package>/, and its SOURCES.txt
# block (the source package it was built from)
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
    add_source_block "$pkg" "$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}' "$pkg")" "$(rpm -q --qf '%{LICENSE}' "$pkg")" \
        "$(rpm -q --qf '%{SOURCERPM}' "$pkg") ($(. /etc/os-release && echo "$NAME $VERSION_ID") source repositories, e.g. dnf download --source $pkg)" \
        "" "Shared library taken unchanged (stripped, RPATH set) from the build image ($(. /etc/os-release && echo "$PRETTY_NAME")) for rpm."
    echo "  📄 LICENSES/$pkg: $(cd "$dest" && ls | tr '\n' ' ')"
}

RPM_STAGE="$WORK/rpm-stage"
if [ "$WITH_RPM" = "1" ]; then
    RPM_TARBALL=$(source_tarball RPM "$SOURCES") WORK_DIR="$WORK/rpm" bash "$ASSETS/rpm/build-linux.sh" "$RPM_STAGE"

    echo "📄 Mapping the rpm bundle's binaries to their licenses"
    [ -s "$RPM_STAGE/LICENSES/COPYING.rpm" ] || die "rpm bundle has no LICENSES/COPYING.rpm"
    mkdir -p "$STAGE/LICENSES/rpm"
    cp "$RPM_STAGE/LICENSES/COPYING.rpm" "$STAGE/LICENSES/rpm/COPYING"
    add_source_block rpm "$RPM_VERSION" "$RPM_LICENSE" "$RPM_URL" "$RPM_SHA256" \
        "bin/rpm and bin/rpmbuild (wrappers), libexec/, lib/librpm*, lib/rpm/: built by rpm/build-linux.sh with patches: $(cd "$ASSETS/rpm/patches" && ls | tr '\n' ' ')"
    while IFS= read -r bin; do
        case "$bin" in
            libexec/* | lib/librpm* | lib/rpm/*) add_binaries rpm "$bin" ;;
            lib/*/*) die "$bin: no license mapping for this binary" ;;
            lib/*)
                name=$(basename "$bin")
                sys=$(find /usr/lib64 /lib64 /usr/lib /lib -maxdepth 1 -name "$name" 2>/dev/null | sed -n 1p)
                [ -n "$sys" ] || die "$bin: $name is not installed in the build image; cannot find its package"
                pkg=$(rpm -qf --qf '%{NAME}\n' "$sys" | sort -u)
                [ -n "$pkg" ] && [ "$(printf '%s\n' "$pkg" | awk 'END {print NR}')" -eq 1 ] ||
                    die "$bin: expected one package to own $sys, got: $(echo "$pkg" | tr '\n' ' ')"
                rpm_package_license "$pkg" "$bin"
                add_binaries "$pkg" "$bin"
                ;;
            *) die "$bin: no license mapping for this binary" ;;
        esac
    done < <(bash "$VERIFY_LICENSES" --list "$RPM_STAGE")
    # share/misc/magic.mgc is libmagic's database, from the same package as libmagic (file-libs)
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
    echo "archive toolset: linux $(uname -m), built on $(. /etc/os-release && echo "$PRETTY_NAME"), $(ldd --version | sed -n 1p)"
    echo "compiler: $(gcc --version | sed -n 1p)"
    for c in XZ LZIP TAR BINUTILS ZLIB LIBMD LIBARCHIVE; do
        echo "$(echo "$c" | tr '[:upper:]' '[:lower:]'): $(component_var "$c" VERSION) (sha256 $(component_var "$c" SHA256))"
    done
    cat "$WORK/tools/versions.txt"
    if [ "$WITH_RPM" = "1" ]; then sed 's/^/rpm bundle: /' "$RPM_STAGE/VERSION.txt"; fi
    grep -E '^ *max-' "$WORK/verify.txt" | sed 's/^ *//' || true
} >"$STAGE/VERSION.txt"
cat "$STAGE/VERSION.txt"
du -sh "$STAGE"
echo "✅ archive toolset staged at $STAGE"
