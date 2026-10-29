#!/usr/bin/env bash
# Versions, sources and sha256 pins of everything in the archive toolset. Sourced by the build scripts.
# shellcheck disable=SC2034 # consumed by the scripts that source this file
#
# To bump a component: download the new tarball and its signature, verify the signature with the signer's key
# fetched by the fingerprint listed below (gpg --recv-keys <fingerprint>; gpg --verify <file>.sig <file>), then
# update the version and the sha256 (sha256sum <file>). The build checks the sha256.

# XZ Utils: bin/xz. Signed by Lasse Collin, 3690C240CE51B4670D30AD1C38EE757D69184620
# renovate: datasource=github-releases depName=tukaani-project/xz extractVersion=^v(?<version>.+)$
XZ_VERSION=5.8.4
XZ_URL="https://github.com/tukaani-project/xz/releases/download/v$XZ_VERSION/xz-$XZ_VERSION.tar.gz"
XZ_SHA256=0014c7886930454fe8bd4228665b51af55eeae560ea135c9c4cd33f55b2591d9

# lzip: bin/lzip. Signed by Antonio Diaz Diaz, 1E5AEE0B18C0DEB45D64AA0325B62C9821501AA0
# renovate: datasource=repology depName=lzip packageName=homebrew/lzip
LZIP_VERSION=1.26
LZIP_URL="https://download.savannah.nongnu.org/releases/lzip/lzip-$LZIP_VERSION.tar.gz"
LZIP_SHA256=641cf30961525cbe3b340cc883436c8854e9f5032f459f444de4782b621e6572

# GNU tar: bin/tar, bin/gtar. Signed by Sergey Poznyakoff, 325F650C4C2B6AD58807327A3602B07F55D0C732
# renovate: datasource=repology depName=gnu-tar packageName=homebrew/gnu-tar
TAR_VERSION=1.35
TAR_URL="https://ftpmirror.gnu.org/tar/tar-$TAR_VERSION.tar.gz"
TAR_SHA256=14d55e32063ea9526e057fbf35fcabd53378e769787eff7919c3755b02d2b57e

# GNU binutils: bin/ar, bin/gar. Signed by Nick Clifton, 3A24BC1E8FB409FA9F14371813FCEF89DD9E3C4F
# renovate: datasource=repology depName=binutils packageName=homebrew/binutils
BINUTILS_VERSION=2.47
BINUTILS_URL="https://ftpmirror.gnu.org/binutils/binutils-$BINUTILS_VERSION.tar.bz2"
BINUTILS_SHA256=3068128c75cda9f898ccb4211d360246e8e195ffcc9dfb655b23ae23a54800e8

# libarchive: bin/bsdtar. Signed by Martin Matuska, 659C84C0E23EA1FA97E0B58CC040B508D63D2B36
# renovate: datasource=github-releases depName=libarchive/libarchive extractVersion=^v(?<version>.+)$
LIBARCHIVE_VERSION=3.8.10
LIBARCHIVE_URL="https://github.com/libarchive/libarchive/releases/download/v$LIBARCHIVE_VERSION/libarchive-$LIBARCHIVE_VERSION.tar.xz"
LIBARCHIVE_SHA256=56cad765459d5ee25a3b761f90c47d99379d28297fbfb72d908880d6b875fb96

# Linux only, linked statically (macOS has its own):
# zlib, gzip for bsdtar and ar. Signed by Mark Adler, 5ED46A6721D365587791E2AA783FCD8E58BCAFBA
# renovate: datasource=github-releases depName=madler/zlib extractVersion=^v(?<version>.+)$
ZLIB_VERSION=1.3.2
ZLIB_URL="https://zlib.net/zlib-$ZLIB_VERSION.tar.gz"
ZLIB_SHA256=bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16
# libmd, md5/sha256 for bsdtar's mtree (fpm's pacman .MTREE). Signed by Guillem Jover, 4F3E74F436050C10F5696574B972BF3EA4AE57A3
# renovate: datasource=repology depName=libmd packageName=homebrew/libmd
LIBMD_VERSION=1.3.0
LIBMD_URL="https://archive.hadrons.org/software/libmd/libmd-$LIBMD_VERSION.tar.xz"
LIBMD_SHA256=fc0f1eb6b6766470326f2c014693809190e67dba84274a6fbae9d4912d066706

# rpm: bin/rpm, bin/rpmbuild on linux amd64/arm64 and darwin arm64. Upstream does not sign the tarball.
# renovate: datasource=github-releases depName=rpm-software-management/rpm extractVersion=^rpm-(?<version>.+)-release$
RPM_VERSION=6.1.0
RPM_URL="https://github.com/rpm-software-management/rpm/releases/download/rpm-$RPM_VERSION-release/rpm-$RPM_VERSION.tar.bz2"
RPM_SHA256=f520810d27c74bf1c5d8b8885845c61e0c845f62d33e68b02e020633a8b62fe3

# Oldest macOS the binaries run on
MACOS_MIN=15.0

# rpm build options: only what rpmbuild needs for fpm (no Sequoia/OpenPGP, plugins or host integrations)
RPM_CMAKE_ARGS=(
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=lib
    -DCMAKE_INSTALL_SYSCONFDIR=/etc -DCMAKE_INSTALL_LOCALSTATEDIR=/var -DCMAKE_INSTALL_SHAREDSTATEDIR=/var/lib
    -DENABLE_NLS=OFF -DENABLE_OPENMP=OFF -DENABLE_PYTHON=OFF -DENABLE_PLUGINS=OFF -DENABLE_SQLITE=OFF
    -DENABLE_NDB=ON -DENABLE_TESTSUITE=OFF -DWITH_SEQUOIA=OFF -DWITH_CAP=OFF -DWITH_ACL=OFF -DWITH_SELINUX=OFF
    -DWITH_DBUS=OFF -DWITH_AUDIT=OFF -DWITH_FAPOLICYD=OFF -DWITH_READLINE=OFF -DWITH_IMAEVM=OFF -DWITH_FSVERITY=OFF
)
# rpm config dir entries not shipped (libarchive helpers, rpmdb/cron/valgrind tooling)
RPM_CONFIGDIR_DROP=(rpmuncompress rpm2archive rpmdb_dump rpmdb_load rpm.daily rpm.log rpm.supp rpm-setup-autosign)
