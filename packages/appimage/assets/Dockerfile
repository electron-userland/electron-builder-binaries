# Multi-platform Dockerfile for building AppImage tools
# Build with: docker buildx build --platform linux/amd64,linux/arm64,linux/arm/v7 -t appimage-builder .

FROM buildpack-deps:18.04 AS builder

ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT

ENV DEBIAN_FRONTEND=noninteractive

# Reset apt sources to update old package signatures (issues on ARM)
RUN set -eux; \
    if [ "$TARGETARCH" = "arm64" ] || [ "$TARGETARCH" = "arm" ]; then \
        echo "🔧 Using ports.ubuntu.com for ARM"; \
        sed -i 's|http://archive.ubuntu.com/ubuntu|http://ports.ubuntu.com/ubuntu-ports|g' /etc/apt/sources.list; \
    else \
        echo "🔧 Using archive.ubuntu.com for x86"; \
        sed -i 's|http://ports.ubuntu.com/ubuntu-ports|http://archive.ubuntu.com/ubuntu|g' /etc/apt/sources.list; \
    fi; \
    apt-get update || true && \
    apt-get install -y --no-install-recommends ubuntu-keyring gnupg ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install build dependencies
RUN rm -rf /var/lib/apt/lists/* \
    && apt-get clean \
    && apt-get update -yq && apt-get install -y \
    autoconf \
    automake \
    build-essential \
    cmake \
    desktop-file-utils \
    file \
    gettext \
    git \
    libgconf-2-4 \
    libglib2.0-dev \
    liblz4-dev \
    liblzma-dev \
    liblzo2-dev \
    libnotify4 \
    libtool \
    libxss1 \
    libxtst6 \
    libzstd-dev \
    meson \
    ninja-build \
    patchelf \
    pkg-config \
    tar \
    tree \
    wget \
    zlib1g-dev \    
    zip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    case "$TARGETPLATFORM" in \
      "linux/386") \
        echo "📥 Downloading libappindicator1 from Ubuntu 18.04 archive (i386)..."; \
        cd /tmp; \
        wget -q http://archive.ubuntu.com/ubuntu/pool/universe/liba/libappindicator/libappindicator1_12.10.1+18.04.20180322.1-0ubuntu1_i386.deb; \
        wget -q http://archive.ubuntu.com/ubuntu/pool/universe/libi/libindicator/libindicator7_16.10.0+18.04.20180321.1-0ubuntu1_i386.deb; \
        mkdir -p /tmp/appind /tmp/ind; \
        dpkg -x libappindicator1_12.10.1+18.04.20180322.1-0ubuntu1_i386.deb /tmp/appind; \
        dpkg -x libindicator7_16.10.0+18.04.20180321.1-0ubuntu1_i386.deb /tmp/ind; \
        echo "   ✅ i386 libappindicator packages extracted"; \
        ;; \
      *) \
        echo "📥 Installing libappindicator3-1 & libindicator3-7..."; \
        apt-get update; \
        apt-get install -y --no-install-recommends \
          libappindicator3-1 \
          libindicator3-7; \
        ;; \
    esac; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*;

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-setuptools \
    python3-wheel \
 && pip3 install --no-cache-dir "meson>=0.61" \
 && ln -sf /usr/local/bin/meson /usr/bin/meson \
 && apt-get clean && rm -rf /var/lib/apt/lists/* \
 && meson --version

RUN mkdir -p /project/build

WORKDIR /project/build

ARG DESKTOP_UTILS_DEPS_VERSION_TAG="0.28"
ENV DESKTOP_UTILS_DEPS_VERSION_TAG=${DESKTOP_UTILS_DEPS_VERSION_TAG}

ARG SQUASHFS_TOOLS_VERSION_TAG="4.6.1"
ENV SQUASHFS_TOOLS_VERSION_TAG=${SQUASHFS_TOOLS_VERSION_TAG}

ARG OPENJPEG_VERSION="2.5.4"
ENV OPENJPEG_VERSION=${OPENJPEG_VERSION}

COPY ./assets/build-appimage.sh /project/build/build-appimage.sh
RUN DEST=/ bash /project/build/build-appimage.sh

# Final stage - create minimal output image for caching (specifically for local dev)
FROM scratch
ARG TARGETARCH
ARG TARGETVARIANT
COPY --from=builder /appimage-tools-linux-${TARGETARCH}${TARGETVARIANT}.tar.gz /appimage-tools-linux-${TARGETARCH}${TARGETVARIANT}.tar.gz