# Dockerfile for building Wine for Linux x86_64
# Can be built on ARM64 macOS using Docker Desktop with --platform flag

FROM --platform=linux/amd64 ubuntu:22.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    flex \
    bison \
    gcc-mingw-w64 \
    libc6-dev \
    libfreetype6-dev \
    libgnutls28-dev \
    libpng-dev \
    libxml2-dev \
    libxslt1-dev \
    zlib1g-dev \
    libncurses-dev \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev \
    libvulkan-dev \
    libudev-dev \
    libsdl2-dev \
    libcups2-dev \
    libdbus-1-dev \
    libfontconfig1-dev \
    libfreetype6-dev \
    libgphoto2-dev \
    liblcms2-dev \
    libldap2-dev \
    libpulse-dev \
    libsane-dev \
    libtiff-dev \
    libunwind-dev \
    libusb-1.0-0-dev \
    libx11-dev \
    libxcomposite-dev \
    libxcursor-dev \
    libxext-dev \
    libxi-dev \
    libxinerama-dev \
    libxrandr-dev \
    libxrender-dev \
    libxxf86vm-dev \
    unzip \
    xvfb \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Create build directory
WORKDIR /build

# Script will be mounted or copied
COPY build-in-docker.sh /build/build-in-docker.sh
COPY generate-trace-exes.sh /build/generate-trace-exes.sh
RUN chmod +x /build/build-in-docker.sh /build/generate-trace-exes.sh

# Output directory
VOLUME /output

CMD ["/build/build-in-docker.sh"]