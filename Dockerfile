ARG PLATFORM_ARCH=amd64
ARG DOCKER_IMAGE_BASE=buildpack-deps:bookworm-curl
FROM --platform=linux/$PLATFORM_ARCH $DOCKER_IMAGE_BASE

# Install dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bzip2 \
        ca-certificates \
        desktop-file-utils \
        g++ \
        gcc \
        git \
        libc-dev \
        liblzma-dev \
        liblzo2-dev \
        libssl-dev \
        make \
        p7zip-full \
        # python2 \
        python3 \
        python3-pip \
        python3-setuptools \
        python3-wheel \
        tar \
        tree \
        unzip \
        wget \
        cmake \
        ruby \
        rpm \
        zlib1g-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/build-dir

# prepare makensis and build
ARG NSIS_VERSION=3.11
ARG SCONS_VERSION=4.9.1
RUN mkdir -p /tmp/scons && curl -L http://prdownloads.sourceforge.net/scons/scons-local-$SCONS_VERSION.tar.gz | tar -xz -C /tmp/scons && \
    mkdir -p /tmp/nsis && curl -L https://sourceforge.net/projects/nsis/files/NSIS%203/$NSIS_VERSION/nsis-$NSIS_VERSION-src.tar.bz2/download | tar -xj -C /tmp/nsis --strip-components 1 && \
    cd /tmp/nsis && \
    python3 /tmp/scons/scons.py STRIP=0 SKIPSTUBS=all SKIPPLUGINS=all SKIPUTILS=all SKIPMISC=all NSIS_CONFIG_CONST_DATA_PATH=no NSIS_CONFIG_LOG=yes NSIS_MAX_STRLEN=8192 makensis
RUN cp /tmp/nsis/build/urelease/makensis/makensis /usr/local/bin

# zstd and mksquashfs
ARG ZSTD_VERSION=1.5.0
ARG SQUASHFS_VERSION=4.5
RUN git clone --depth 1 --branch v$ZSTD_VERSION https://github.com/facebook/zstd.git && cd zstd && make -j5 install && cd .. && \
    git clone --depth 1 --branch $SQUASHFS_VERSION https://github.com/plougher/squashfs-tools && cd squashfs-tools/squashfs-tools && \
    make -j5 XZ_SUPPORT=1 LZO_SUPPORT=1 ZSTD_SUPPORT=1 GZIP_SUPPORT=0 COMP_DEFAULT=zstd install

# osslsigncode (requires newer cmake 3.17+)
ARG OSSLSIGNCODE_VERSION=2.9
RUN curl -L https://github.com/mtrojnar/osslsigncode/archive/refs/tags/$OSSLSIGNCODE_VERSION.zip -o f.zip && \ 
    unzip f.zip && rm f.zip
# RUN curl -L https://github.com/Kitware/CMake/releases/download/v4.0.1/cmake-4.0.1-linux-x86_64.sh -o f.sh  && \ 
#     mkdir /opt/cmake && sh f.sh --skip-license --include-subdir --prefix=/opt/cmake && \ 
#     ln -s /opt/cmake/cmake-4.0.1-linux-x86_64/bin/cmake /usr/local/bin/cmake
RUN cd osslsigncode-$OSSLSIGNCODE_VERSION && \
    mkdir build && \
    cd build && \
    cmake -S .. && cmake --build .  && \ 
    cp /tmp/build-dir/osslsigncode-$OSSLSIGNCODE_VERSION/build/osslsigncode /usr/local/bin/osslsigncode

# build scripts
WORKDIR /usr/src/app
COPY ./docker-scripts /usr/src/app/docker-scripts

# build resources
COPY ./packages/nsis-lang-fixes /usr/src/app/packages/nsis-lang-fixes

ARG FPM_VERSION=1.16.0
RUN FPM_VERSION=$FPM_VERSION sh ./docker-scripts/fpm.sh

RUN sh ./docker-scripts/nsis-windows.sh
RUN sh ./docker-scripts/nsis-plugins.sh
RUN sh ./docker-scripts/wix-toolset-x64.sh
RUN sh ./docker-scripts/appimage-openjpeg-x64.sh
RUN sh ./docker-scripts/squirrel-windows.sh
RUN sh ./docker-scripts/appImage-packages-x64.sh
RUN sh ./docker-scripts/appImage-packages-ia32.sh
RUN sh ./docker-scripts/win-codesign-tools.sh
