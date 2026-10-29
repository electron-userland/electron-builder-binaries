#!/usr/bin/env bash
# Builds the xz CLI (XZ Utils) from the pinned, checksum-verified upstream release into <stage>/bin/xz.
# liblzma is linked statically, so the binary depends on the C library only. Its license goes to
# <stage>/LICENSES/xz-utils/ and its entry to <stage>/LICENSES/MANIFEST.tsv.
#
# Linux: run inside the build image (see build-native-linux.sh). macOS: run on the runner; the binary
# targets the runner's architecture and MACOS_MIN (packages/rpm/assets/constants.sh).
#
# Usage: build-xz.sh <stage-dir>
# Env:   XZ_TARBALL  use a pre-downloaded tarball (still sha256-verified)
#        WORK_DIR    scratch directory (default: /tmp/xz-build)
set -euo pipefail

ASSETS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# verify_sha256, MACOS_MIN and the glibc ceiling are shared with the rpm toolset
# shellcheck source=SCRIPTDIR/../../rpm/assets/constants.sh
source "$ASSETS/../../rpm/assets/constants.sh"
# shellcheck source=SCRIPTDIR/native-constants.sh
source "$ASSETS/native-constants.sh"

STAGE="${1:?usage: build-xz.sh <stage-dir>}"
WORK="${WORK_DIR:-/tmp/xz-build}"
OS=$(uname -s)

rm -rf "$WORK"
mkdir -p "$WORK" "$STAGE/bin" "$STAGE/LICENSES/xz-utils"
STAGE=$(cd "$STAGE" && pwd)

tarball="${XZ_TARBALL:-$WORK/xz-${XZ_VERSION}.tar.gz}"
if [ ! -f "$tarball" ]; then
    echo "⬇️  Downloading xz ${XZ_VERSION}"
    curl -fsSL --retry 3 --retry-delay 2 --max-time 300 "$XZ_URL" -o "$tarball"
fi
verify_sha256 "$tarball" "$XZ_SHA256"
tar -xzf "$tarball" -C "$WORK"
SRC="$WORK/xz-${XZ_VERSION}"

CONFIGURE_ARGS=(
    --prefix="$WORK/install"
    --disable-shared
    --enable-static
    --disable-nls
    --disable-doc
    --disable-scripts
    --disable-xzdec
    --disable-lzmadec
    --disable-lzmainfo
    --disable-lzma-links
    --disable-dependency-tracking
)
if [ "$OS" = "Darwin" ]; then
    ARCH=$(uname -m)
    export MACOSX_DEPLOYMENT_TARGET="$MACOS_MIN"
    export CC="clang -arch $ARCH"
    export CFLAGS="-O2 -mmacosx-version-min=$MACOS_MIN"
    export LDFLAGS="-mmacosx-version-min=$MACOS_MIN"
    JOBS=$(sysctl -n hw.ncpu)
else
    export CFLAGS="-O2"
    JOBS=$(nproc)
fi

# shellcheck disable=SC2086 # CC may carry flags (clang -arch ...)
echo "🔨 Building xz ${XZ_VERSION} ($(uname -m), $(${CC:-cc} --version 2>/dev/null | sed -n 1p))"
(
    cd "$SRC"
    ./configure "${CONFIGURE_ARGS[@]}" >"$WORK/configure.log" 2>&1 || { tail -40 "$WORK/configure.log"; exit 1; }
    make -j"$JOBS" >"$WORK/make.log" 2>&1 || { tail -60 "$WORK/make.log"; exit 1; }
    make install >"$WORK/install.log" 2>&1 || { tail -40 "$WORK/install.log"; exit 1; }
)

XZ_BIN="$STAGE/bin/xz"
cp "$WORK/install/bin/xz" "$XZ_BIN"
chmod 755 "$XZ_BIN"

echo "🔍 Checking that xz depends on the C library only"
if [ "$OS" = "Darwin" ]; then
    strip "$XZ_BIN"
    codesign --force --sign - "$XZ_BIN"
    deps=$(otool -L "$XZ_BIN" | tail -n +2 | awk '{print $1}')
    echo "$deps" | sed 's/^/    /'
    if echo "$deps" | grep -qv '^/usr/lib/libSystem\.B\.dylib$'; then
        echo "❌ xz links more than libSystem" >&2
        exit 1
    fi
    minos=$(otool -l "$XZ_BIN" | awk '/LC_BUILD_VERSION/{b=1} b&&/minos/{print $2; b=0}')
    echo "    minos: $minos"
    if [ "$(printf '%s\n%s\n' "$minos" "$MACOS_MIN" | sort -V | tail -1)" != "$MACOS_MIN" ]; then
        echo "❌ xz requires macOS $minos > $MACOS_MIN" >&2
        exit 1
    fi
else
    strip --strip-unneeded "$XZ_BIN"
    deps=$(env -u LD_LIBRARY_PATH ldd "$XZ_BIN" | awk '{print $1}')
    echo "$deps" | sed 's/^/    /'
    if echo "$deps" | grep -qvE '^(linux-vdso|linux-gate|/lib.*/ld-linux|ld-linux|libc\.so|libpthread\.so|librt\.so)'; then
        echo "❌ xz links more than the C library" >&2
        exit 1
    fi
fi
"$XZ_BIN" --version
echo "eb-native-tools" | "$XZ_BIN" -z -T0 | "$XZ_BIN" -dc | grep -qx 'eb-native-tools'
echo "  ✓ xz round-trip"

echo "📄 Collecting the XZ Utils license"
# COPYING says which license covers which part: xz and liblzma are 0BSD (COPYING.0BSD). The GPL/LGPL parts
# (scripts, the getopt_long replacement) are not built.
for f in COPYING COPYING.0BSD; do
    [ -s "$SRC/$f" ] || { echo "❌ $f is missing from the xz ${XZ_VERSION} source" >&2; exit 1; }
    cp "$SRC/$f" "$STAGE/LICENSES/xz-utils/$f"
done
{
    echo "bin/xz: XZ Utils ${XZ_VERSION}, built from the upstream release tarball with liblzma linked statically."
    echo "  Source: ${XZ_URL}"
    echo "  sha256: ${XZ_SHA256}"
} >"$STAGE/LICENSES/xz-utils/SOURCE.txt"
printf 'bin/xz\txz-utils\n' >>"$STAGE/LICENSES/MANIFEST.tsv"
echo "✅ xz ${XZ_VERSION} staged at $XZ_BIN ($(wc -c <"$XZ_BIN" | tr -d ' ') bytes)"
