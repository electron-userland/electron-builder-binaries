# syntax=docker/dockerfile:1

ARG PLATFORM_ARCH=amd64
# renovate: datasource=github-tags depName=mtrojnar/osslsigncode
ARG OSSLSIGNCODE_VER=2.14
# renovate: datasource=github-releases depName=Kitware/CMake extractVersion=^v(?<version>.+)$
ARG CMAKE_VERSION=3.28.3

# For i386, we build on amd64 with multilib. For others, use native platform.
FROM ubuntu:20.04 AS builder

# Docker BuildKit automatically provides these when using --platform
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT

# Our custom arch parameter
ARG PLATFORM_ARCH
ARG OSSLSIGNCODE_VER
ARG CMAKE_VERSION

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH=/opt/cmake/bin:$PATH

RUN echo "Building on $BUILDPLATFORM for $TARGETPLATFORM" && \
    echo "PLATFORM_ARCH=$PLATFORM_ARCH TARGETARCH=$TARGETARCH"

# Build tools only: OpenSSL and libp11 are built from source by build-linux-osslsigncode.sh
# and bundled, so no distro libssl/libcurl dev packages (nothing can link against them).
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl git build-essential perl pkg-config zlib1g-dev \
    zip unzip ca-certificates xz-utils \
    patchelf file binutils \
    && rm -rf /var/lib/apt/lists/*

# For i386 builds, install multilib and the 32-bit zlib
RUN if [ "$PLATFORM_ARCH" = "i386" ] || [ "$PLATFORM_ARCH" = "ia32" ]; then \
        dpkg --add-architecture i386 && \
        apt-get update && apt-get install -y --no-install-recommends \
        gcc-multilib g++-multilib \
        lib32stdc++6 \
        zlib1g-dev:i386 \
        && rm -rf /var/lib/apt/lists/* ; \
    fi

# Install CMake (detect architecture for ARM, use x86_64 for x86/i386)
RUN ARCH=$(uname -m) && \
    echo "Detected architecture: $ARCH" && \
    if [ "$ARCH" = "x86_64" ]; then \
        CMAKE_ARCH="x86_64" ; \
    elif [ "$ARCH" = "aarch64" ]; then \
        CMAKE_ARCH="aarch64" ; \
    elif [ "$ARCH" = "i686" ] || [ "$ARCH" = "i386" ]; then \
        CMAKE_ARCH="x86_64" ; \
    else \
        echo "Unsupported CMake architecture: $ARCH" && exit 1 ; \
    fi && \
    echo "Downloading CMake for: $CMAKE_ARCH" && \
    curl -sSL -o /tmp/cmake.tar.gz \
    https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-${CMAKE_ARCH}.tar.gz \
    && mkdir -p /opt/cmake \
    && tar --strip-components=1 -xzf /tmp/cmake.tar.gz -C /opt/cmake \
    && rm /tmp/cmake.tar.gz

# Verify CMake works
RUN cmake --version

COPY ./assets/deps-versions.sh ./assets/compiler-flags.sh ./assets/verify-linux-linkage.sh \
     ./assets/bundle-osslsigncode.sh ./assets/build-linux-osslsigncode.sh ./assets/licenses.sh /tmp/assets/

# Build OpenSSL + libp11 + osslsigncode and create the portable bundle
RUN bash /tmp/assets/build-linux-osslsigncode.sh \
    --arch "${PLATFORM_ARCH}" \
    --osslsigncode-ver "${OSSLSIGNCODE_VER}" \
    --output-dir /out/linux/osslsigncode

CMD ["/bin/bash"]
