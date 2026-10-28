#!/usr/bin/env bash
# Builds the portable rpm bundle for macOS arm64 from source against Homebrew libraries,
# then copies those dylibs into the bundle and rewrites every reference to @rpath.
#
# Usage: build-mac.sh <output-stage-dir>
set -euo pipefail

[ "$(uname -s)" = "Darwin" ] || { echo "❌ Must be run on macOS"; exit 1; }
[ "$(uname -m)" = "arm64" ] || { echo "❌ Only arm64 is supported"; exit 1; }

ASSETS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=SCRIPTDIR/constants.sh
source "$ASSETS/constants.sh"

STAGE="${1:?usage: build-mac.sh <output-stage-dir>}"
WORK="${WORK_DIR:-/tmp/rpm-build-darwin}"
DESTDIR="$WORK/dest"
BUNDLE="$WORK/bundle"
export MACOSX_DEPLOYMENT_TARGET="$MACOS_MIN"

# gettext: libintl is a transitive dependency of the Homebrew libgcrypt/popt bottles
FORMULAE=(lua popt libarchive libmagic zstd xz libgcrypt libgpg-error gettext)
echo "🍺 Installing build dependencies"
brew install -q cmake pkgconf scdoc coreutils "${FORMULAE[@]}"
BREW_PREFIX="$(brew --prefix)"
PKG_CONFIG_PATH="$(brew --prefix libarchive)/lib/pkgconfig:$BREW_PREFIX/lib/pkgconfig"
export PKG_CONFIG_PATH

SRC=$(fetch_rpm_source "$WORK" "$ASSETS/patches")

echo "🔨 Configuring rpm ${RPM_VERSION} (MACOSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET)"
rm -rf "$WORK/build" "$DESTDIR"
cmake -S "$SRC" -B "$WORK/build" "${RPM_CMAKE_COMMON_ARGS[@]}" \
    -DWITH_LIBELF=OFF -DWITH_LIBDW=OFF \
    -DCMAKE_PREFIX_PATH="$BREW_PREFIX" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
    -DCMAKE_INSTALL_NAME_DIR=@rpath \
    -DCMAKE_MACOSX_RPATH=ON \
    -DCMAKE_EXE_LINKER_FLAGS="-Wl,-headerpad_max_install_names" \
    -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-headerpad_max_install_names" \
    >"$WORK/cmake.log" 2>&1 || { tail -40 "$WORK/cmake.log"; exit 1; }
echo "🔨 Building"
cmake --build "$WORK/build" -j"$(sysctl -n hw.ncpu)" >"$WORK/make.log" 2>&1 || { grep -m10 -B3 -A10 'error' "$WORK/make.log" || tail -60 "$WORK/make.log"; exit 1; }
DESTDIR="$DESTDIR" cmake --install "$WORK/build" >/dev/null

echo "📁 Assembling bundle"
install_bundle_skeleton "$DESTDIR" "$BUNDLE" "$ASSETS"
for so in librpm librpmbuild librpmio librpmsign; do
    # install name is @rpath/<so>.<major>.dylib; ship exactly that file name, no symlinks
    real=$(find "$DESTDIR/usr/lib" -maxdepth 1 -name "$so.*.dylib" -type f | sed -n 1p)
    id=$(otool -D "$real" | tail -1)
    cp "$real" "$BUNDLE/lib/$(basename "$id")"
done

is_macho() { file -b "$1" | grep -q 'Mach-O'; }
macho_files() { find "$BUNDLE" -type f | while read -r f; do if is_macho "$f"; then echo "$f"; fi; done; }
deps_of() { otool -L "$1" | tail -n +2 | awk '{print $1}'; }

echo "  🔗 Copying Homebrew dylibs and rewriting install names"
changed=1
while [ "$changed" = "1" ]; do
    changed=0
    while read -r f; do
        while read -r dep; do
            case "$dep" in
                "$BREW_PREFIX"/* | /usr/local/*) ;;
                *) continue ;;
            esac
            base=$(basename "$dep")
            if [ ! -f "$BUNDLE/lib/$base" ]; then
                echo "    + $base ($dep)"
                cp -L "$dep" "$BUNDLE/lib/$base"
                chmod 644 "$BUNDLE/lib/$base"
                install_name_tool -id "@rpath/$base" "$BUNDLE/lib/$base" 2>/dev/null
                changed=1
            fi
            install_name_tool -change "$dep" "@rpath/$base" "$f" 2>/dev/null
        done < <(deps_of "$f")
    done < <(macho_files)
done

echo "  🩹 Setting @loader_path rpaths"
while read -r f; do
    rel=$(grealpath --relative-to="$(dirname "$f")" "$BUNDLE/lib")
    if [ "$rel" = "." ]; then rp="@loader_path"; else rp="@loader_path/$rel"; fi
    # drop every existing LC_RPATH (build dir, Homebrew prefix), then add the relative one
    otool -l "$f" | awk '/cmd LC_RPATH/{getline; getline; print $2}' | while read -r old; do
        install_name_tool -delete_rpath "$old" "$f" 2>/dev/null || true
    done
    install_name_tool -add_rpath "$rp" "$f"
done < <(macho_files)

echo "  ✂️  Stripping and ad-hoc signing"
while read -r f; do
    strip -x "$f" 2>/dev/null || true
    codesign --force --sign - "$f"
done < <(macho_files)

cp -L "$(brew --prefix libmagic)/share/misc/magic.mgc" "$BUNDLE/share/misc/magic.mgc"

echo "🔍 Verifying no absolute non-system references remain"
bad=0
while read -r f; do
    while read -r dep; do
        case "$dep" in
            @rpath/* | /usr/lib/* | /System/*) ;;
            *) echo "❌ $f -> $dep"; bad=1 ;;
        esac
    done < <(deps_of "$f")
done < <(macho_files)
[ "$bad" = "0" ]

echo "🔍 Checking minimum macOS version (<= $MACOS_MIN)"
max_minos=$(while read -r f; do
    otool -l "$f" | awk '/LC_BUILD_VERSION/{b=1} b&&/minos/{print $2; b=0}'
done < <(macho_files) | sort -V | tail -1)
echo "max-minos: $max_minos"
if [ "$(printf '%s\n%s\n' "$max_minos" "$MACOS_MIN" | sort -V | tail -1)" != "$MACOS_MIN" ]; then
    echo "❌ a bundled binary requires macOS $max_minos > $MACOS_MIN"
    while read -r f; do echo "  $(basename "$f"): $(otool -l "$f" | awk '/LC_BUILD_VERSION/{b=1} b&&/minos/{print $2; b=0}')"; done < <(macho_files)
    exit 1
fi

echo "📄 Collecting licenses"
cp "$SRC/COPYING" "$BUNDLE/LICENSES/COPYING.rpm"
for formula in "${FORMULAE[@]}"; do
    prefix=$(brew --prefix "$formula")
    for name in COPYING COPYING.LIB COPYING.LESSER LICENSE LICENSE.md LICENCE; do
        [ -f "$prefix/$name" ] && cp "$prefix/$name" "$BUNDLE/LICENSES/$name.$formula"
    done
done

echo "📝 VERSION.txt"
{
    echo "rpm: ${RPM_VERSION}"
    echo "sha256: ${RPM_SHA256}"
    echo "built-on: macOS $(sw_vers -productVersion) ($(uname -m))"
    echo "compiler: $(clang --version | sed -n 1p)"
    echo "patches: $(cd "$ASSETS/patches" && printf '%s ' *.patch)"
    echo "max-minos: $max_minos"
    echo "homebrew: $(for f in "${FORMULAE[@]}"; do brew list --versions "$f"; done | tr '\n' ' ')"
    echo "bundled-libs: $(cd "$BUNDLE/lib" && printf '%s ' *.dylib)"
} >"$BUNDLE/VERSION.txt"

echo "🧪 Sanity check"
"$BUNDLE/bin/rpmbuild" --version
"$BUNDLE/bin/rpm" --eval '_rpmformat=%{_rpmformat} _build_id_links=%{_build_id_links}'

rm -rf "$STAGE"
mkdir -p "$(dirname "$STAGE")"
cp -a "$BUNDLE" "$STAGE"
du -sh "$STAGE"
echo "✅ Bundle staged at $STAGE"
