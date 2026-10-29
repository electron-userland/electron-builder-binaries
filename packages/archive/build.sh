#!/usr/bin/env bash
# Builds packages/archive/out/archive/archive-<os>-<arch>.7z, whose bin/ electron-builder puts first on PATH:
# xz, lzip, GNU tar (tar, gtar), GNU ar (ar, gar), bsdtar, and rpm/rpmbuild on linux amd64/arm64 and darwin arm64.
#   Linux:  ARCH=amd64|arm64|i386 bash packages/archive/build.sh   (manylinux container; use a native-arch runner)
#   macOS:  bash packages/archive/build.sh                         (the runner's architecture)
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$ROOT/../.." && pwd)
source "$ROOT/assets/constants.sh"
SOURCES="$ROOT/build/sources"
mkdir -p "$SOURCES" "$ROOT/out/archive"

if [ "$(uname -s)" = "Darwin" ]; then
    case "$(uname -m)" in
        arm64) NAME=darwin-arm64 WITH_RPM=1 ;;
        *) NAME=darwin-x86_64 WITH_RPM=0 ;;
    esac
else
    case "${ARCH:-amd64}" in
        amd64) NAME=linux-amd64 WITH_RPM=1 PLATFORM=linux/amd64 IMAGE=quay.io/pypa/manylinux_2_28_x86_64 ;;
        arm64) NAME=linux-arm64v8 WITH_RPM=1 PLATFORM=linux/arm64 IMAGE=quay.io/pypa/manylinux_2_28_aarch64 ;;
        # manylinux_2_28 has no i686 image; i386 ships no rpm
        i386) NAME=linux-i386 WITH_RPM=0 PLATFORM=linux/386 IMAGE=quay.io/pypa/manylinux2014_i686 ;;
        *) echo "Unsupported ARCH: $ARCH (amd64, arm64, i386)"; exit 1 ;;
    esac
fi
STAGE="$ROOT/build/stage-$NAME"

# Download every source here, on the host, and check its sha256 pin
fetch() {
    local file
    file="$SOURCES/$(basename "$1")"
    [ -f "$file" ] || curl -fsSL --retry 5 --retry-all-errors -o "$file" "$1"
    echo "$2  $file" | shasum -a 256 -c -
}
fetch "$XZ_URL" "$XZ_SHA256"
fetch "$LZIP_URL" "$LZIP_SHA256"
fetch "$TAR_URL" "$TAR_SHA256"
fetch "$BINUTILS_URL" "$BINUTILS_SHA256"
fetch "$LIBARCHIVE_URL" "$LIBARCHIVE_SHA256"
if [ "$(uname -s)" != "Darwin" ]; then
    fetch "$ZLIB_URL" "$ZLIB_SHA256"
    fetch "$LIBMD_URL" "$LIBMD_SHA256"
fi
if [ "$WITH_RPM" = 1 ]; then fetch "$RPM_URL" "$RPM_SHA256"; fi

if [ "$(uname -s)" = "Darwin" ]; then
    WITH_RPM=$WITH_RPM bash "$ROOT/assets/build-mac.sh" "$STAGE"
else
    docker run --rm --platform "$PLATFORM" -v "$REPO:/repo" -e WITH_RPM="$WITH_RPM" "$IMAGE" bash -c \
        "bash /repo/packages/archive/assets/build-linux.sh /repo/packages/archive/build/stage-$NAME; status=\$?; chown -R $(id -u):$(id -g) /repo/packages/archive/build; exit \$status"
fi

bash "$REPO/scripts/verify-licenses.sh" "$STAGE"
ARCHIVE="$ROOT/out/archive/archive-$NAME.7z"
rm -f "$ARCHIVE"
(cd "$STAGE" && "$(command -v 7za || command -v 7zz || command -v 7z)" a -bd -mx=9 -mfb=64 "$ARCHIVE" ./* >/dev/null)
echo "📦 $(basename "$ARCHIVE"): $(wc -c <"$ARCHIVE" | tr -d ' ') bytes"
cat "$STAGE/VERSION.txt"
