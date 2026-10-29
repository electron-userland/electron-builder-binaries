#!/usr/bin/env bash
# Builds the portable rpm bundle for Linux. Intended to run inside a
# manylinux_2_28 container (AlmaLinux 8, glibc 2.28, gcc-toolset >= 13), see ../build-linux.sh.
#
# Usage: build-linux.sh <output-stage-dir>
# Env:   INSTALL_DEPS=0  skip dnf (for local builds on a host that already has the -devel deps)
#        RPM_TARBALL     use a pre-downloaded rpm tarball (still sha256-verified)
#        MAX_GLIBC / MAX_GLIBCXX / MAX_CXXABI  override the ABI ceiling (local experiments only)
set -euo pipefail

ASSETS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=SCRIPTDIR/constants.sh
source "$ASSETS/constants.sh"

STAGE="${1:?usage: build-linux.sh <output-stage-dir>}"
WORK="${WORK_DIR:-/tmp/rpm-build}"
DESTDIR="$WORK/dest"
BUNDLE="$WORK/bundle"

if [ "${INSTALL_DEPS:-1}" = "1" ] && command -v dnf >/dev/null 2>&1; then
    echo "📦 Installing build dependencies (dnf)"
    dnf -y -q install dnf-plugins-core
    dnf config-manager --set-enabled powertools
    # gettext: rpm configures po/ (msgfmt/xgettext) even with ENABLE_NLS=OFF
    dnf -y -q install \
        cmake make gawk patch bzip2 pkgconf-pkg-config binutils file gettext \
        lua-devel popt-devel file-devel libarchive-devel zlib-devel bzip2-devel xz-devel \
        libzstd-devel elfutils-libelf-devel elfutils-devel libgcrypt-devel
fi

command -v patchelf >/dev/null || { echo "❌ patchelf is required (preinstalled in manylinux images)"; exit 1; }
GCC_MAJOR=$(g++ -dumpversion | cut -d. -f1)
if [ "$GCC_MAJOR" -lt 13 ]; then
    echo "❌ rpm ${RPM_VERSION} needs a C++20 compiler with <format> (GCC >= 13); found GCC $(g++ -dumpversion)"
    echo "   On manylinux_2_28 enable a newer toolset, e.g. 'source /opt/rh/gcc-toolset-14/enable'."
    exit 1
fi
echo "🛠️  $(g++ --version | sed -n 1p)"
echo "🛠️  $(cmake --version | sed -n 1p)"
ldd --version | sed -n 1p

# rpm's build requires scdoc for man pages; the bundle ships no man pages.
if ! command -v scdoc >/dev/null 2>&1; then
    mkdir -p "$WORK/fakebin"
    printf '#!/bin/sh\ncat >/dev/null\n' >"$WORK/fakebin/scdoc"
    chmod 755 "$WORK/fakebin/scdoc"
    export PATH="$WORK/fakebin:$PATH"
fi

# libgcrypt < 1.9 (EL8 ships 1.8.5) has no libgcrypt.pc; rpm finds it via pkg-config only.
if ! pkg-config --exists libgcrypt && command -v libgcrypt-config >/dev/null 2>&1; then
    mkdir -p "$WORK/pkgconfig"
    cat >"$WORK/pkgconfig/libgcrypt.pc" <<PC
Name: libgcrypt
Description: shim generated from libgcrypt-config
Version: $(libgcrypt-config --version)
Cflags: $(libgcrypt-config --cflags)
Libs: $(libgcrypt-config --libs)
PC
    export PKG_CONFIG_PATH="$WORK/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    echo "🩹 Generated libgcrypt.pc shim ($(libgcrypt-config --version))"
fi

SRC=$(fetch_rpm_source "$WORK" "$ASSETS/patches")

echo "🔨 Configuring rpm ${RPM_VERSION}"
rm -rf "$WORK/build" "$DESTDIR"
cmake -S "$SRC" -B "$WORK/build" "${RPM_CMAKE_COMMON_ARGS[@]}" >"$WORK/cmake.log" 2>&1 || { tail -40 "$WORK/cmake.log"; exit 1; }
echo "🔨 Building"
cmake --build "$WORK/build" -j"$(nproc)" >"$WORK/make.log" 2>&1 || { grep -m10 -B3 -A10 'error' "$WORK/make.log" || tail -60 "$WORK/make.log"; exit 1; }
DESTDIR="$DESTDIR" cmake --install "$WORK/build" >/dev/null

echo "📁 Assembling bundle"
install_bundle_skeleton "$DESTDIR" "$BUNDLE" "$ASSETS"
for so in librpm librpmbuild librpmio librpmsign; do
    real=$(find "$DESTDIR/usr/lib" -maxdepth 1 -name "$so.so.*" -type f | sed -n 1p)
    soname=$(objdump -p "$real" | awk '/SONAME/{print $2}')
    cp "$real" "$BUNDLE/lib/$soname"
done

# ELF files we ship (executables + helpers in RPM_CONFIGDIR)
elf_files() {
    find "$BUNDLE" -type f | while read -r f; do
        if [ "$(head -c 4 "$f" | od -An -tx1 | tr -d ' \n')" = "7f454c46" ]; then echo "$f"; fi
    done
}

# Libraries provided by every glibc system (and the GCC runtime): never bundled.
SYSTEM_LIBS='^(linux-vdso|linux-gate|ld-linux|libc\.so|libm\.so|libdl\.so|librt\.so|libpthread\.so|libresolv\.so|libutil\.so|libstdc\+\+\.so|libgcc_s\.so)'
echo "  🔗 Copying third-party shared libraries"
for _ in 1 2 3; do
    elf_files | while read -r f; do
        LD_LIBRARY_PATH="$BUNDLE/lib" ldd "$f" 2>/dev/null | awk '/=> \//{print $1" "$3}' | while read -r name path; do
            [[ "$name" =~ $SYSTEM_LIBS ]] && continue
            [ -e "$BUNDLE/lib/$name" ] && continue
            echo "    + $name ($path)"
            cp -L "$path" "$BUNDLE/lib/$name"
            chmod 644 "$BUNDLE/lib/$name"
        done
    done
done

echo "  🩹 Setting relative RPATHs"
elf_files | while read -r f; do
    rel=$(realpath --relative-to="$(dirname "$f")" "$BUNDLE/lib")
    # shellcheck disable=SC2016 # $ORIGIN is for the dynamic loader, not the shell
    if [ "$rel" = "." ]; then rp='$ORIGIN'; else rp="\$ORIGIN/$rel"; fi
    # DT_RPATH (not RUNPATH): wins over an inherited LD_LIBRARY_PATH, e.g. the one the
    # fpm toolset's ruby.env exports for its own libz.
    patchelf --force-rpath --set-rpath "$rp" "$f"
done

echo "  ✂️  Stripping"
elf_files | xargs strip --strip-unneeded

MAGIC_SRC=""
for m in /usr/share/misc/magic.mgc /usr/share/file/magic.mgc /usr/lib/file/magic.mgc; do
    if [ -f "$m" ]; then MAGIC_SRC="$m"; break; fi
done
[ -n "$MAGIC_SRC" ] || { echo "❌ magic.mgc not found"; exit 1; }
cp -L "$MAGIC_SRC" "$BUNDLE/share/misc/magic.mgc"

echo "🔍 Checking that every ELF resolves from the bundle"
missing=0
while read -r f; do
    if env -u LD_LIBRARY_PATH ldd "$f" 2>&1 | grep -q 'not found'; then
        echo "❌ unresolved libraries in $f:"; ldd "$f" | grep 'not found'; missing=1
    fi
done < <(elf_files)
[ "$missing" = "0" ]

bash "$ASSETS/check-linux-abi.sh" "$BUNDLE" | tee "$WORK/abi.txt"

echo "📄 Collecting licenses"
cp "$SRC/COPYING" "$BUNDLE/LICENSES/COPYING.rpm"
if command -v rpm >/dev/null 2>&1 && rpm -q rpm >/dev/null 2>&1; then
    for lib in "$BUNDLE"/lib/*.so*; do
        case "$(basename "$lib")" in librpm*) continue ;; esac
        sys=$(find /usr/lib64 /usr/lib /lib64 -maxdepth 1 -name "$(basename "$lib")" 2>/dev/null | sed -n 1p)
        [ -n "$sys" ] || continue
        pkg=$(rpm -qf --qf '%{NAME}\n' "$sys" 2>/dev/null | sed -n 1p) || continue
        rpm -qL "$pkg" 2>/dev/null | while read -r lic; do
            [ -f "$lic" ] && cp "$lic" "$BUNDLE/LICENSES/$(basename "$lic").$pkg"
        done
    done
    mfpkg=$(rpm -qf --qf '%{NAME}\n' "$MAGIC_SRC" | sed -n 1p)
    rpm -qL "$mfpkg" 2>/dev/null | while read -r lic; do [ -f "$lic" ] && cp "$lic" "$BUNDLE/LICENSES/$(basename "$lic").$mfpkg"; done
elif command -v dpkg >/dev/null 2>&1; then
    for lib in "$BUNDLE"/lib/*.so* "$MAGIC_SRC"; do
        case "$(basename "$lib")" in librpm*) continue ;; esac
        pkg=$(dpkg -S "$(basename "$lib")" 2>/dev/null | sed -n 1p | cut -d: -f1) || continue
        [ -f "/usr/share/doc/$pkg/copyright" ] && cp "/usr/share/doc/$pkg/copyright" "$BUNDLE/LICENSES/copyright.$pkg"
    done
fi

echo "📝 VERSION.txt"
{
    echo "rpm: ${RPM_VERSION}"
    echo "sha256: ${RPM_SHA256}"
    echo "built-on: $(. /etc/os-release && echo "$PRETTY_NAME") ($(uname -m))"
    echo "compiler: $(g++ --version | sed -n 1p)"
    echo "patches: $(cd "$ASSETS/patches" && printf '%s ' *.patch)"
    cat "$WORK/abi.txt"
    echo "bundled-libs: $(cd "$BUNDLE/lib" && printf '%s ' *.so*)"
} >"$BUNDLE/VERSION.txt"

echo "🧪 Sanity check"
"$BUNDLE/bin/rpmbuild" --version
"$BUNDLE/bin/rpm" --eval '_rpmformat=%{_rpmformat} _build_id_links=%{_build_id_links}'

rm -rf "$STAGE"
mkdir -p "$(dirname "$STAGE")"
cp -a "$BUNDLE" "$STAGE"
du -sh "$STAGE"
echo "✅ Bundle staged at $STAGE"
