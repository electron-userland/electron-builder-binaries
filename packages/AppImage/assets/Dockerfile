# Multi-platform Dockerfile for building AppImage tools
# Build with: docker buildx build --platform linux/amd64,linux/arm64,linux/arm/v7 -t appimage-builder .

ARG TARGETPLATFORM
ARG PLATFORM_PREFIX=

FROM ${PLATFORM_PREFIX}ubuntu:20.04 AS builder

ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update -yq && apt-get install -y \
    build-essential \
    git \
    wget \
    zlib1g-dev \
    liblzma-dev \
    liblz4-dev \
    libzstd-dev \
    liblzo2-dev \
    libglib2.0-dev \
    desktop-file-utils \
    cmake \
    file \
    && rm -rf /var/lib/apt/lists/*

# Clone squashfs-tools
WORKDIR /build
ARG SQUASHFS_TOOLS_VERSION_TAG="4.6.1"
RUN git clone https://github.com/plougher/squashfs-tools.git && \
    cd squashfs-tools/squashfs-tools && \
    git checkout $SQUASHFS_TOOLS_VERSION_TAG

# Copy build script and execute
COPY ./assets/appimage-docker.sh /build/
RUN chmod +x /build/appimage-docker.sh && \
    /build/appimage-docker.sh

# Final stage - create minimal output image
FROM scratch
ARG TARGETARCH
ARG TARGETVARIANT
COPY --from=builder /appimage-tools-${TARGETARCH}${TARGETVARIANT}.tar.gz /appimage-tools-${TARGETARCH}${TARGETVARIANT}.tar.gz