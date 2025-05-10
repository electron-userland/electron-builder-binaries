# !/usr/bin/env bash
set -euo pipefail

export RUBY_VERSION=3.4.3

CWD=$(cd "$(dirname "$BASH_SOURCE")" && pwd)
BASEDIR=$CWD/out
mkdir -p $BASEDIR

OS_TARGET=${OS_TARGET:-$(uname | tr '[:upper:]' '[:lower:]')}

if [ "$OS_TARGET" = "darwin" ]; then
    echo "Building for macOS"
    bash "$CWD/assets/compile-portable-ruby.sh"
else
    # These are the --platform linux/ARCH options available for buildpack-deps:bookworm-curl
    # Pulled from: https://hub.docker.com/_/buildpack-deps/tags?name=bookworm-curl
    ARCH_OPTIONS="amd64 arm/v5 arm/v7 arm64/v8 386 mips64le ppc64le s390x"
    echo "Building for Linux"
    if [ -z "$ARCH" ]; then
        echo "Architecture not specified. Options are: $ARCH_OPTIONS."
        echo "Defaulting to amd64."
        ARCH="amd64"
    fi
    if [[ "$ARCH_OPTIONS" != *"$ARCH"* ]]; then
        echo "Unknown architecture: $ARCH. Options supported: $ARCH_OPTIONS."
        echo "Please set the ARCH environment variable to one of these values."
        echo "Example: ARCH=amd64 ./path/to/build.sh"
        exit 1
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
        -f "$CWD/assets/Dockerfile" \
        --build-arg RUBY_VERSION=$RUBY_VERSION \
        --build-arg TARGETARCH=$ARCH \
        --progress=plain \
        -t $DOCKER_TAG \
        $CWD
    # --no-cache \ # Add to above to force rebuild
    docker run --cidfile="$cidFile" $DOCKER_TAG

    containerId=$(cat "$cidFile")

    FPM_OUTPUT_DIR=$CWD
    mkdir -p $FPM_OUTPUT_DIR
    docker cp -a "$containerId":/tmp/out $FPM_OUTPUT_DIR

    cleanup
fi
echo "Build completed successfully."
