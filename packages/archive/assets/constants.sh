#!/usr/bin/env bash
# Shared configuration for the archive toolset build scripts. Sourced, not executed (bash 3.2 compatible: macOS).
# shellcheck disable=SC2034 # variables are consumed by the scripts that source this file
#
# Every component is built from its upstream release tarball, pinned by sha256 and, where upstream signs its
# releases, checked against the signing key(s) in keys/<fingerprint>.asc (public keys exported from
# keyserver.ubuntu.com with `gpg --export-options export-minimal`). fetch-sources.sh downloads and verifies them on
# the build host; the build scripts verify the sha256 again before extracting.
#
# <NAME>_URLS     space separated mirrors of the same file (the first one that works is used)
# <NAME>_SIG      signature suffix appended to the URL that served the tarball ("" = upstream does not sign)
# <NAME>_KEYS     fingerprints of the primary keys allowed to have made that signature
# To bump a component: update the version and sha256 (verify the signature first:
#   gpg --import keys/<fpr>.asc && gpg --verify <tarball>.sig <tarball> && sha256sum <tarball>)
# and LICENSE_FILES below if the license files changed.

ARCHIVE_ASSETS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# rpm's version, sha256 and URL, build options, MACOS_MIN and the glibc ceiling (MAX_GLIBC)
# shellcheck source=SCRIPTDIR/rpm/constants.sh
source "$ARCHIVE_ASSETS/rpm/constants.sh"

ARCHIVE_COMPONENTS="XZ LZIP TAR BINUTILS ZLIB LIBMD LIBARCHIVE RPM"

# XZ Utils (bin/xz; liblzma is linked statically into xz and bsdtar). 0BSD.
XZ_VERSION="5.8.4"
XZ_SHA256="0014c7886930454fe8bd4228665b51af55eeae560ea135c9c4cd33f55b2591d9"
XZ_URLS="https://github.com/tukaani-project/xz/releases/download/v${XZ_VERSION}/xz-${XZ_VERSION}.tar.gz"
XZ_SIG=".sig"
XZ_KEYS="3690C240CE51B4670D30AD1C38EE757D69184620" # Lasse Collin
XZ_LICENSE="0BSD"
XZ_LICENSE_FILES="COPYING COPYING.0BSD"

# lzip (bin/lzip): electron-builder's tar.lz target. GPL-2.0-or-later.
LZIP_VERSION="1.26"
LZIP_SHA256="641cf30961525cbe3b340cc883436c8854e9f5032f459f444de4782b621e6572"
LZIP_URLS="https://download.savannah.nongnu.org/releases/lzip/lzip-${LZIP_VERSION}.tar.gz https://download-mirror.savannah.gnu.org/releases/lzip/lzip-${LZIP_VERSION}.tar.gz"
LZIP_SIG=".sig"
LZIP_KEYS="1D41C14B272A2219A739FA4F8FE99503132D7742 1E5AEE0B18C0DEB45D64AA0325B62C9821501AA0" # Antonio Diaz Diaz
LZIP_LICENSE="GPL-2.0-or-later"
LZIP_LICENSE_FILES="COPYING AUTHORS"

# GNU tar (bin/tar, bin/gtar): fpm's tar_cmd (--sort=name --mtime=@0), freebsd's `tar --transform`. GPL-3.0-or-later.
TAR_VERSION="1.35"
TAR_SHA256="14d55e32063ea9526e057fbf35fcabd53378e769787eff7919c3755b02d2b57e"
TAR_URLS="https://ftpmirror.gnu.org/tar/tar-${TAR_VERSION}.tar.gz https://ftp.gnu.org/gnu/tar/tar-${TAR_VERSION}.tar.gz"
TAR_SIG=".sig"
TAR_KEYS="325F650C4C2B6AD58807327A3602B07F55D0C732" # Sergey Poznyakoff
TAR_LICENSE="GPL-3.0-or-later"
TAR_LICENSE_FILES="COPYING AUTHORS"

# GNU binutils (bin/ar, bin/gar): fpm's ar_cmd for deb, deterministic (-D) by default.
# ar, libbfd and libsframe are GPL-3.0-or-later; libiberty is LGPL.
BINUTILS_VERSION="2.47"
BINUTILS_SHA256="3068128c75cda9f898ccb4211d360246e8e195ffcc9dfb655b23ae23a54800e8"
BINUTILS_URLS="https://ftpmirror.gnu.org/binutils/binutils-${BINUTILS_VERSION}.tar.bz2 https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.bz2 https://sourceware.org/pub/binutils/releases/binutils-${BINUTILS_VERSION}.tar.bz2"
BINUTILS_SIG=".sig"
BINUTILS_KEYS="3A24BC1E8FB409FA9F14371813FCEF89DD9E3C4F" # Nick Clifton
BINUTILS_LICENSE="GPL-3.0-or-later AND LGPL-3.0-or-later AND GPL-2.0-or-later AND LGPL-2.0-or-later"
BINUTILS_LICENSE_FILES="COPYING COPYING.LIB COPYING3 COPYING3.LIB"

# zlib, Linux only (macOS uses the system libz): linked statically into bsdtar (gzip, e.g. pacman's .MTREE) and ar.
ZLIB_VERSION="1.3.2"
ZLIB_SHA256="bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16"
ZLIB_URLS="https://zlib.net/zlib-${ZLIB_VERSION}.tar.gz https://github.com/madler/zlib/releases/download/v${ZLIB_VERSION}/zlib-${ZLIB_VERSION}.tar.gz"
ZLIB_SIG=".asc"
ZLIB_KEYS="5ED46A6721D365587791E2AA783FCD8E58BCAFBA" # Mark Adler
ZLIB_LICENSE="Zlib"
ZLIB_LICENSE_FILES="LICENSE"

# libmd, Linux only (macOS uses CommonCrypto): MD5/SHA-256 for the md5digest/sha256digest of pacman's .MTREE
# (bsdtar --format=mtree). Linked statically into bsdtar.
LIBMD_VERSION="1.3.0"
LIBMD_SHA256="fc0f1eb6b6766470326f2c014693809190e67dba84274a6fbae9d4912d066706"
LIBMD_URLS="https://archive.hadrons.org/software/libmd/libmd-${LIBMD_VERSION}.tar.xz https://libbsd.freedesktop.org/releases/libmd-${LIBMD_VERSION}.tar.xz"
LIBMD_SIG=".asc"
LIBMD_KEYS="4F3E74F436050C10F5696574B972BF3EA4AE57A3" # Guillem Jover
LIBMD_LICENSE="BSD-3-Clause AND BSD-2-Clause AND ISC AND Beerware AND LicenseRef-Public-Domain"
LIBMD_LICENSE_FILES="COPYING"

# libarchive (bin/bsdtar): fpm's pacman target writes .MTREE with bsdtar. BSD-2-Clause.
LIBARCHIVE_VERSION="3.8.10"
LIBARCHIVE_SHA256="56cad765459d5ee25a3b761f90c47d99379d28297fbfb72d908880d6b875fb96"
LIBARCHIVE_URLS="https://github.com/libarchive/libarchive/releases/download/v${LIBARCHIVE_VERSION}/libarchive-${LIBARCHIVE_VERSION}.tar.xz https://www.libarchive.org/downloads/libarchive-${LIBARCHIVE_VERSION}.tar.xz"
LIBARCHIVE_SIG=".asc"
LIBARCHIVE_KEYS="659C84C0E23EA1FA97E0B58CC040B508D63D2B36 DB2C7CF1B4C265FAEF56E3FC5848A18B8F14184B A5A45B12AD92D964B89EEE2DEC560C81CEC2276E" # Martin Matuska
LIBARCHIVE_LICENSE="BSD-2-Clause"
LIBARCHIVE_LICENSE_FILES="COPYING"

# rpm (bin/rpm, bin/rpmbuild, libexec/, lib/, share/): linux amd64/arm64 and darwin arm64 only, built by
# rpm/build-{linux,mac}.sh exactly as the rpm@1.0.0 toolset was. Version and sha256 live in rpm/constants.sh;
# upstream does not sign the release tarball. GPL-2.0-or-later (librpm* LGPL-2.1-or-later as an option).
RPM_URLS="$RPM_URL"
RPM_SIG=""
RPM_KEYS=""
RPM_LICENSE="GPL-2.0-or-later"
RPM_LICENSE_FILES="COPYING"

# Linux build images. amd64/arm64: manylinux_2_28 (AlmaLinux 8, glibc 2.28). manylinux_2_28 has no i686 image, so
# i386 is built on manylinux2014 (CentOS 7, glibc 2.17) and ships no rpm.
IMAGE_amd64="${IMAGE_amd64:-quay.io/pypa/manylinux_2_28_x86_64:latest}"
IMAGE_arm64="${IMAGE_arm64:-quay.io/pypa/manylinux_2_28_aarch64:latest}"
IMAGE_i386="${IMAGE_i386:-quay.io/pypa/manylinux2014_i686:latest}"

# The tools every archive's bin/ ships, and the ones only the rpm platforms add
ARCHIVE_BINS="xz lzip tar gtar ar gar bsdtar"
RPM_BINS="rpm rpmbuild"

die() {
    echo "❌ $*" >&2
    exit 1
}

# component_var <COMPONENT> <FIELD>: the value of <COMPONENT>_<FIELD> (bash 3.2: no namerefs)
component_var() {
    local name="$1_$2"
    printf '%s' "${!name-}"
}

# tarball_name <COMPONENT>: the file name the source is saved as
tarball_name() {
    local urls
    urls=$(component_var "$1" URLS)
    basename "${urls%% *}"
}

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

# verify_sha256 <file> <expected>
verify_sha256() {
    local file="$1" expected="$2" actual
    actual=$(sha256_of "$file")
    if [ "$actual" != "$expected" ]; then
        echo "❌ Checksum mismatch for $(basename "$file")" >&2
        echo "   expected: $expected" >&2
        echo "   actual:   $actual" >&2
        return 1
    fi
    echo "  ✓ sha256 $(basename "$file")"
}

# source_tarball <COMPONENT> <sources-dir>: path of the verified tarball (sha256 checked again)
source_tarball() {
    local file
    file="$2/$(tarball_name "$1")"
    [ -f "$file" ] || die "$(tarball_name "$1") is not in $2 (run fetch-sources.sh first)"
    verify_sha256 "$file" "$(component_var "$1" SHA256)" >&2
    echo "$file"
}

# extract_source <COMPONENT> <sources-dir> <work-dir>: extracts the verified tarball, prints the source directory
extract_source() {
    local tarball dir
    tarball=$(source_tarball "$1" "$2")
    mkdir -p "$3"
    # GNU tar (>= 1.22) and bsdtar detect the compression themselves, but GNU tar needs the decompressor program
    # (an image may lack bzip2): fall back to Python's tarfile
    if ! tar -xf "$tarball" -C "$3" 2>"$3/.extract.log"; then
        local py
        py=$(command -v python3 || ls /opt/python/cp3*/bin/python3 2>/dev/null | tail -n 1 || true)
        [ -n "$py" ] || { cat "$3/.extract.log" >&2; die "cannot extract $(basename "$tarball")"; }
        echo "  tar could not extract $(basename "$tarball") ($(head -n 1 "$3/.extract.log")); using $py" >&2
        "$py" -I -c 'import sys, tarfile; tarfile.open(sys.argv[1]).extractall(sys.argv[2])' "$tarball" "$3"
    fi
    rm -f "$3/.extract.log"
    dir=$(basename "$tarball")
    dir="$3/${dir%.tar.*}"
    [ -d "$dir" ] || die "$(basename "$tarball") did not extract to $dir"
    echo "$dir"
}
