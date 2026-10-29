#!/usr/bin/env bash
# Shared configuration for the rpm build scripts of the archive toolset. Sourced, not executed.
# shellcheck disable=SC2034 # variables are consumed by the scripts that source this file

# Upstream release: https://github.com/rpm-software-management/rpm/releases/tag/rpm-6.1.0-release
# Re-pin when bumping RPM_VERSION: curl -fsSL "$RPM_URL" | sha256sum
RPM_VERSION="${RPM_VERSION:-6.1.0}"
RPM_SHA256="${RPM_SHA256:-f520810d27c74bf1c5d8b8885845c61e0c845f62d33e68b02e020633a8b62fe3}"
RPM_URL="${RPM_URL:-https://github.com/rpm-software-management/rpm/releases/download/rpm-${RPM_VERSION}-release/rpm-${RPM_VERSION}.tar.bz2}"

# Linux ABI ceiling (manylinux_2_28 policy: AlmaLinux 8 / glibc 2.28, GCC 8 runtime).
MAX_GLIBC="${MAX_GLIBC:-2.28}"
MAX_GLIBCXX="${MAX_GLIBCXX:-3.4.25}"
MAX_CXXABI="${MAX_CXXABI:-1.3.11}"

# macOS floor. Matches the macos-15 runners the archive toolset is built on: Homebrew
# bottles copied into the bundle carry the runner OS as their minimum version.
MACOS_MIN="${MACOS_MIN:-15.0}"

# Features rpmbuild does not need for electron-builder's fpm usage. Sequoia is
# off (no Rust toolchain, no OpenPGP signing/verification), as are all optional
# runtime integrations that would add host library dependencies.
RPM_CMAKE_COMMON_ARGS=(
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_INSTALL_PREFIX=/usr
    -DCMAKE_INSTALL_LIBDIR=lib
    -DCMAKE_INSTALL_SYSCONFDIR=/etc
    -DCMAKE_INSTALL_LOCALSTATEDIR=/var
    -DCMAKE_INSTALL_SHAREDSTATEDIR=/var/lib
    -DENABLE_NLS=OFF
    -DENABLE_OPENMP=OFF
    -DENABLE_PYTHON=OFF
    -DENABLE_PLUGINS=OFF
    -DENABLE_SQLITE=OFF
    -DENABLE_NDB=ON
    -DENABLE_TESTSUITE=OFF
    -DWITH_SEQUOIA=OFF
    -DWITH_CAP=OFF
    -DWITH_ACL=OFF
    -DWITH_SELINUX=OFF
    -DWITH_DBUS=OFF
    -DWITH_AUDIT=OFF
    -DWITH_FAPOLICYD=OFF
    -DWITH_READLINE=OFF
    -DWITH_IMAEVM=OFF
    -DWITH_FSVERITY=OFF
)

# Files from the rpm install that the bundle does not ship.
#  - rpmuncompress/rpm2archive pull in libarchive (and ICU on some hosts); fpm specs have no %setup.
#  - rpmdb/cron/valgrind helpers are irrelevant for building packages.
RPM_CONFIGDIR_DROP=(
    rpmuncompress
    rpm2archive
    rpmdb_dump
    rpmdb_load
    rpm.daily
    rpm.log
    rpm.supp
    rpm-setup-autosign
)

verify_sha256() {
    local file="$1" expected="$2" actual
    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "$file" | awk '{print $1}')
    else
        actual=$(shasum -a 256 "$file" | awk '{print $1}')
    fi
    if [ "$actual" != "$expected" ]; then
        echo "❌ Checksum mismatch for $(basename "$file")" >&2
        echo "   expected: $expected" >&2
        echo "   actual:   $actual" >&2
        return 1
    fi
    echo "  ✓ Checksum verified: $(basename "$file")"
}

# fetch_rpm_source <workdir>: downloads (or reuses $RPM_TARBALL), verifies, extracts and
# patches the rpm source. Prints nothing on stdout except the source directory path.
fetch_rpm_source() {
    local workdir="$1" patches_dir="$2" tarball
    mkdir -p "$workdir"
    tarball="${RPM_TARBALL:-$workdir/rpm-${RPM_VERSION}.tar.bz2}"
    if [ ! -f "$tarball" ]; then
        echo "⬇️  Downloading rpm ${RPM_VERSION}" >&2
        curl -fsSL --retry 3 --retry-delay 2 --max-time 300 "$RPM_URL" -o "$tarball"
    fi
    verify_sha256 "$tarball" "$RPM_SHA256" >&2
    rm -rf "$workdir/rpm-${RPM_VERSION}"
    tar -xjf "$tarball" -C "$workdir"
    local p
    for p in "$patches_dir"/*.patch; do
        [ -f "$p" ] || continue
        echo "🩹 Applying $(basename "$p")" >&2
        patch -d "$workdir/rpm-${RPM_VERSION}" -p1 --forward --silent <"$p" >&2
    done
    echo "$workdir/rpm-${RPM_VERSION}"
}

# install_bundle_skeleton <destdir> <bundle> <assets>: copies the rpm config dir, wrappers and
# pinned macros from an rpm `make install DESTDIR=` tree into the bundle layout:
#   bin/{rpmbuild,rpm}   sh wrappers (relocatable, host-macro isolated)
#   libexec/{rpmbuild,rpm}  real executables
#   lib/                 librpm* and bundled third-party libraries
#   lib/rpm/             RPM_CONFIGDIR (macros, platform, fileattrs, helper scripts)
#   share/misc/magic.mgc libmagic database matching the bundled libmagic
install_bundle_skeleton() {
    local destdir="$1" bundle="$2" assets="$3" f t
    rm -rf "$bundle"
    mkdir -p "$bundle/bin" "$bundle/libexec" "$bundle/lib" "$bundle/share/misc" "$bundle/LICENSES"
    for t in rpmbuild rpm; do
        cp "$destdir/usr/bin/$t" "$bundle/libexec/$t"
    done
    cp -R "$destdir/usr/lib/rpm" "$bundle/lib/rpm"
    for f in "${RPM_CONFIGDIR_DROP[@]}"; do
        rm -rf "${bundle:?}/lib/rpm/$f"
    done
    # rpm records helper tools as absolute paths found at configure time (%__rm /usr/bin/rm,
    # %__gzip /usr/bin/gzip, ...). Those break on hosts without merged /usr (e.g. Debian 11,
    # where it is /bin/rm) and point at build-host-only tools, so resolve them via PATH instead.
    local macros="$bundle/lib/rpm/macros"
    sed -E 's#^(%__[A-Za-z0-9_]+[[:space:]]+)/(usr/)?(local/)?s?bin/([^[:space:]/]+)[[:space:]]*$#\1\4#' "$macros" >"$macros.tmp"
    echo "  🔧 Tool macros resolved via PATH: $(diff "$macros" "$macros.tmp" | grep -c '^>' || true)"
    mv "$macros.tmp" "$macros"
    mkdir -p "$bundle/lib/rpm/electron-builder"
    cp "$assets/electron-builder.macros" "$bundle/lib/rpm/electron-builder/macros"
    for t in rpmbuild rpm; do
        cp "$assets/wrapper.sh" "$bundle/bin/$t"
        chmod 755 "$bundle/bin/$t"
    done
}
