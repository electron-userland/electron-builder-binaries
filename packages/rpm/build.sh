#!/usr/bin/env bash
# Builds the portable rpm toolset.
#   Linux:  ARCH=amd64|arm64 bash packages/rpm/build.sh   (docker; native arch runner recommended)
#   macOS:  OS_TARGET=darwin bash packages/rpm/build.sh   (arm64 only)
# Output: packages/rpm/out/rpm/rpm-<version>-<os>-<arch>.7z
set -euo pipefail

CWD=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=SCRIPTDIR/assets/constants.sh
source "$CWD/assets/constants.sh"
OS_TARGET=${OS_TARGET:-$(uname | tr '[:upper:]' '[:lower:]')}
OUTPUT_DIR="$CWD/out/rpm"
mkdir -p "$OUTPUT_DIR"

compress() {
    local stage="$1" archive="$2" sz
    sz=$(command -v 7za || command -v 7zz || command -v 7z || true)
    [ -n "$sz" ] || { echo "❌ 7za/7zz/7z not found"; exit 1; }
    rm -f "$archive"
    (cd "$stage" && "$sz" a -bd -mx=9 -mfb=64 "$archive" ./* >/dev/null)
    echo "📦 $(basename "$archive"): $(wc -c <"$archive" | tr -d ' ') bytes (unpacked $(du -sk "$stage" | cut -f1) KiB)"
}

if [ "$OS_TARGET" = "darwin" ]; then
    if [ "$(uname -m)" != "arm64" ]; then
        echo "❌ Only darwin arm64 is built. Intel macOS users keep toolsets.rpm: 'system'."
        exit 1
    fi
    STAGE="$CWD/build/stage-darwin-arm64"
    bash "$CWD/assets/build-mac.sh" "$STAGE"
    compress "$STAGE" "$OUTPUT_DIR/rpm-${RPM_VERSION}-darwin-arm64.7z"
else
    ARCH=${ARCH:-amd64}
    case "$ARCH" in
        amd64) MANYLINUX_ARCH=x86_64; ARCHIVE_ARCH=amd64 ;;
        arm64 | arm64/v8) MANYLINUX_ARCH=aarch64; ARCHIVE_ARCH=arm64v8 ;;
        *) echo "❌ Unsupported ARCH: $ARCH (amd64, arm64)"; exit 1 ;;
    esac
    IMAGE="${MANYLINUX_IMAGE:-quay.io/pypa/manylinux_2_28_${MANYLINUX_ARCH}:latest}"
    STAGE="$CWD/build/stage-linux-$ARCHIVE_ARCH"
    echo "🐧 Building rpm ${RPM_VERSION} for linux/$ARCH in $IMAGE"
    docker pull --platform "linux/$ARCH" "$IMAGE"
    docker image inspect --format '🐳 {{index .RepoDigests 0}}' "$IMAGE" || true
    rm -rf "$STAGE"
    # WORK_DIR on the bind mount keeps cmake/make logs on the host for CI failure reports
    docker run --rm --platform "linux/$ARCH" \
        -v "$CWD:/work" -w /work -e WORK_DIR="/work/build/work-$ARCHIVE_ARCH" \
        "$IMAGE" \
        bash -c "bash /work/assets/build-linux.sh /work/build/stage-linux-$ARCHIVE_ARCH && chown -R $(id -u):$(id -g) /work/build"
    compress "$STAGE" "$OUTPUT_DIR/rpm-${RPM_VERSION}-linux-${ARCHIVE_ARCH}.7z"
fi
echo "✅ Build completed: $(ls "$OUTPUT_DIR")"
