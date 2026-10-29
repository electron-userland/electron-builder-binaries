#!/usr/bin/env bash
# Builds the archive toolset: one 7z per platform whose bin/ electron-builder puts first on PATH (xz, lzip, GNU tar
# as tar and gtar, GNU ar as ar and gar, bsdtar; rpm and rpmbuild on linux amd64/arm64 and darwin arm64).
#   Linux:  ARCH=amd64|arm64|i386 bash packages/archive/build.sh   (docker, manylinux; use a native-arch runner)
#   macOS:  bash packages/archive/build.sh                         (the runner's architecture)
# Output: packages/archive/out/archive/archive-<os>-<arch>.7z
# The sources are downloaded and verified on this host first (assets/fetch-sources.sh, needs curl and gpg).
set -euo pipefail

CWD=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$CWD/../.." && pwd)
# shellcheck source=SCRIPTDIR/assets/constants.sh
source "$CWD/assets/constants.sh"
OS_TARGET=${OS_TARGET:-$(uname | tr '[:upper:]' '[:lower:]')}
OUTPUT_DIR="$CWD/out/archive"
SOURCES="$CWD/build/sources"
mkdir -p "$OUTPUT_DIR" "$SOURCES"

compress() {
    local stage="$1" archive="$2" sz
    sz=$(command -v 7za || command -v 7zz || command -v 7z || true)
    [ -n "$sz" ] || die "7za/7zz/7z not found"
    rm -f "$archive"
    (cd "$stage" && "$sz" a -bd -mx=9 -mfb=64 "$archive" ./* >/dev/null)
    echo "📦 $(basename "$archive"): $(wc -c <"$archive" | tr -d ' ') bytes (unpacked $(du -sk "$stage" | cut -f1) KiB)"
}

if [ "$OS_TARGET" = "darwin" ]; then
    case "$(uname -m)" in
        arm64) ARCHIVE_ARCH=arm64; COMPONENTS="XZ LZIP TAR BINUTILS LIBARCHIVE RPM" ;;
        x86_64) ARCHIVE_ARCH=x86_64; COMPONENTS="XZ LZIP TAR BINUTILS LIBARCHIVE" ;;
        *) die "Unsupported macOS architecture: $(uname -m)" ;;
    esac
    # shellcheck disable=SC2086 # the component list is space separated
    bash "$CWD/assets/fetch-sources.sh" "$SOURCES" $COMPONENTS
    STAGE="$CWD/build/stage-darwin-$ARCHIVE_ARCH"
    WORK_DIR="$CWD/build/work-darwin-$ARCHIVE_ARCH" bash "$CWD/assets/build-mac.sh" "$SOURCES" "$STAGE"
    compress "$STAGE" "$OUTPUT_DIR/archive-darwin-$ARCHIVE_ARCH.7z"
else
    ARCH=${ARCH:-amd64}
    case "$ARCH" in
        amd64) PLATFORM=linux/amd64; ARCHIVE_ARCH=amd64; IMAGE="$IMAGE_amd64"; WITH_RPM=1 ;;
        arm64 | arm64/v8) PLATFORM=linux/arm64; ARCHIVE_ARCH=arm64v8; IMAGE="$IMAGE_arm64"; WITH_RPM=1 ;;
        # manylinux2014 (glibc 2.17): the i386 binaries need nothing newer
        i386) PLATFORM=linux/386; ARCHIVE_ARCH=i386; IMAGE="$IMAGE_i386"; WITH_RPM=0
            export MAX_GLIBC=2.17 MAX_GLIBCXX=3.4.19 MAX_CXXABI=1.3.7 ;;
        *) die "Unsupported ARCH: $ARCH (amd64, arm64, i386)" ;;
    esac
    COMPONENTS="XZ LZIP TAR BINUTILS ZLIB LIBMD LIBARCHIVE"
    if [ "$WITH_RPM" = "1" ]; then COMPONENTS="$COMPONENTS RPM"; fi
    # shellcheck disable=SC2086 # the component list is space separated
    bash "$CWD/assets/fetch-sources.sh" "$SOURCES" $COMPONENTS

    STAGE="$CWD/build/stage-linux-$ARCHIVE_ARCH"
    echo "🐧 Building the archive toolset for $PLATFORM in $IMAGE"
    docker pull --platform "$PLATFORM" "$IMAGE"
    docker image inspect --format '🐳 {{index .RepoDigests 0}}' "$IMAGE" || true
    rm -rf "$STAGE"
    # The repository is mounted (the build uses scripts/verify-licenses.sh); WORK_DIR on the mount keeps the
    # configure/make logs on the host for CI failure reports. The manylinux entrypoint runs i686 under linux32.
    rel="packages/archive"
    docker run --rm --platform "$PLATFORM" -v "$REPO:/repo" -w /repo \
        -e WITH_RPM="$WITH_RPM" -e WORK_DIR="/repo/$rel/build/work-linux-$ARCHIVE_ARCH" -e GITHUB_SHA="${GITHUB_SHA:-}" \
        -e MAX_GLIBC="${MAX_GLIBC:-2.28}" -e MAX_GLIBCXX="${MAX_GLIBCXX:-3.4.25}" -e MAX_CXXABI="${MAX_CXXABI:-1.3.11}" \
        "$IMAGE" \
        bash -c "status=0; bash /repo/$rel/assets/build-linux.sh /repo/$rel/build/sources /repo/$rel/build/stage-linux-$ARCHIVE_ARCH || status=\$?; chown -R $(id -u):$(id -g) /repo/$rel/build; exit \$status"
    compress "$STAGE" "$OUTPUT_DIR/archive-linux-$ARCHIVE_ARCH.7z"
fi
echo "✅ Build completed: $(ls "$OUTPUT_DIR")"
