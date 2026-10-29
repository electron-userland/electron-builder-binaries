#!/usr/bin/env bash
set -euo pipefail

export RUBY_VERSION=3.4.12

CWD=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
OS_TARGET=${OS_TARGET:-$(uname | tr '[:upper:]' '[:lower:]')}

# Fast checks of the license collection and the native tools merge before the long build
echo "🧪 Testing the license collection (tests/collect-licenses-test.sh)..."
bash "$CWD/tests/collect-licenses-test.sh"
echo "🧪 Testing the native tools merge (tests/add-native-tools-test.sh)..."
bash "$CWD/tests/add-native-tools-test.sh"

# Archives older than this marker come from earlier builds and are not checked at the end
BUILD_MARKER="$(mktemp "${TMPDIR:-/tmp}/fpm-build-marker.XXXXXX")"

if [ "$OS_TARGET" = "darwin" ]; then
    # cleanup docker container on error
    f() {
        errorCode=$? # save the exit code as the first thing done in the trap function
        echo "error $errorCode"
        echo "the command executing at the time of the error was"
        echo "$BASH_COMMAND"
        echo "on line ${BASH_LINENO[0]}"
        exit $errorCode
    }
    trap f ERR

    echo "Building for macOS"
    bash "$CWD/assets/compile-portable-ruby.sh"
    bash "$CWD/assets/patch-portable-ruby.sh"

    # Native tools for the bundle's bin/: xz, and rpm on arm64
    NATIVE_STAGE="$CWD/build/native-darwin-$(uname -m)"
    WORK_DIR="$CWD/build/work-native-darwin" bash "$CWD/assets/build-native-mac.sh" "$NATIVE_STAGE"
else
    # These are the --platform linux/ARCH options supported: debian:buster (Ruby) and a manylinux image for
    # the native tools (native-constants.sh) exist for each
    ARCH_OPTIONS="i386 amd64 arm64/v8"
    echo "Building for Linux"
    if [ -z "$ARCH" ]; then
        echo "Architecture not specified. Options are: $ARCH_OPTIONS."
        ARCH="amd64"
        echo "Defaulting to $ARCH."
    fi
    if [[ "$ARCH_OPTIONS" != *"$ARCH"* ]]; then
        echo "Unknown architecture: $ARCH. Options supported: $ARCH_OPTIONS."
        echo "Please set the ARCH environment variable to one of these values."
        echo "Example: ARCH=amd64 ./path/to/build.sh"
        exit 1
    fi
    if [ "$ARCH" = "i386" ]; then
        PLATFORM_ARCH="386"
    else
        PLATFORM_ARCH="$ARCH"
    fi
    echo "Building for architecture: $ARCH"

    ARCH_KEY=$(echo "$ARCH" | tr '/' '-')
    cidFile="/tmp/linux-build-container-id-$ARCH_KEY"
    cleanup() {
        if test -f "$cidFile"; then
            containerId=$(cat "$cidFile")
            echo "Stopping docker container $containerId."
            docker rm "$containerId"
            unlink "$cidFile"
        fi
    }
    # check if previous docker containers are still running based off of container lockfile
    cleanup

    # cleanup docker container on error
    f() {
        errorCode=$? # save the exit code as the first thing done in the trap function
        echo "error $errorCode"
        echo "the command executing at the time of the error was"
        echo "$BASH_COMMAND"
        echo "on line ${BASH_LINENO[0]}"

        cleanup

        exit $errorCode
    }
    trap f ERR

    DOCKER_TAG="fpm-builder:$ARCH_KEY"
    docker buildx build \
        --load \
        --build-arg PLATFORM_ARCH="$PLATFORM_ARCH" \
        --build-arg TARGET_ARCH="$ARCH" \
        --build-arg RUBY_VERSION="$RUBY_VERSION" \
        --progress=plain \
        --build-context repo-scripts="$CWD/../../scripts" \
        -f "$CWD/assets/Dockerfile" \
        -t "$DOCKER_TAG" \
        "$CWD"
    docker run --cidfile="$cidFile" "$DOCKER_TAG"

    containerId=$(cat "$cidFile")

    FPM_OUTPUT_DIR=$CWD
    mkdir -p "$FPM_OUTPUT_DIR"
    docker cp -a "$containerId":/tmp/out "$FPM_OUTPUT_DIR"

    cleanup

    # Native tools for the bundle's bin/: xz, and rpm on amd64/arm64 (manylinux_2_28 has no i686)
    # shellcheck source=SCRIPTDIR/assets/native-constants.sh
    source "$CWD/assets/native-constants.sh"
    case "$ARCH" in
        amd64) NATIVE_PLATFORM=linux/amd64; NATIVE_IMAGE="$NATIVE_IMAGE_amd64"; WITH_RPM=1 ;;
        arm64/v8) NATIVE_PLATFORM=linux/arm64; NATIVE_IMAGE="$NATIVE_IMAGE_arm64"; WITH_RPM=1 ;;
        i386) NATIVE_PLATFORM=linux/386; NATIVE_IMAGE="$NATIVE_IMAGE_i386"; WITH_RPM=0 ;;
    esac
    REPO_DIR=$(cd "$CWD/../.." && pwd)
    NATIVE_STAGE="$CWD/build/native-linux-$ARCH_KEY"
    echo "🐧 Building the native tools for $NATIVE_PLATFORM in $NATIVE_IMAGE"
    docker pull --platform "$NATIVE_PLATFORM" "$NATIVE_IMAGE"
    docker image inspect --format '🐳 {{index .RepoDigests 0}}' "$NATIVE_IMAGE" || true
    mkdir -p "$CWD/build"
    # WORK_DIR on the bind mount keeps the build logs on the host for CI failure reports
    docker run --rm --platform "$NATIVE_PLATFORM" \
        -v "$REPO_DIR:/repo" -w /repo \
        -e WITH_RPM="$WITH_RPM" \
        -e WORK_DIR="/repo/packages/fpm/build/work-native-$ARCH_KEY" \
        "$NATIVE_IMAGE" \
        bash -c "rc=0; bash /repo/packages/fpm/assets/build-native-linux.sh /repo/packages/fpm/build/native-linux-$ARCH_KEY || rc=\$?; chown -R $(id -u):$(id -g) /repo/packages/fpm/build; exit \$rc"
fi

NEW_ARCHIVES=()
while IFS= read -r archive; do
    NEW_ARCHIVES+=("$archive")
done < <(find "$CWD/out/fpm" -name '*.7z' -newer "$BUILD_MARKER" | sort)
rm -f "$BUILD_MARKER"
if [ "${#NEW_ARCHIVES[@]}" -ne 1 ]; then
    echo "❌ Expected one archive built in $CWD/out/fpm, found ${#NEW_ARCHIVES[@]}: ${NEW_ARCHIVES[*]:-none}" >&2
    exit 1
fi

bash "$CWD/assets/add-native-tools.sh" "${NEW_ARCHIVES[0]}" "$NATIVE_STAGE"

# The build itself fails on a missing license (patch-portable-ruby.sh); check the archives that ship as well
echo "🔍 Checking the licenses in the built archives..."
bash "$CWD/assets/verify-archive-licenses.sh" "${NEW_ARCHIVES[@]}"
echo "Build completed successfully."
