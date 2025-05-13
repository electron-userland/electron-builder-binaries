# syntax=docker/dockerfile:1.4

ARG TARGET_ARCH=x86_64
ARG PLATFORM_ARCH=x86_64
ARG RUBY_VERSION=3.4.3
# ARG DOCKER_IMAGE=buildpack-deps:bookworm-curl
ARG DOCKER_IMAGE=buildpack-deps:22.04-curl

FROM --platform=linux/${PLATFORM_ARCH} ${DOCKER_IMAGE} AS build

ENV DEBIAN_FRONTEND=noninteractive

# ---- Build stage ----
# Install build dependencies
RUN apt-get update -qq && apt-get install -yq \
    gcc g++ make autoconf bison git \
    libssl-dev libreadline-dev libyaml-dev \
    zlib1g-dev libffi-dev libgdbm-dev \
    file patchelf tar ruby-dev valgrind \
    openssl libz-dev libyaml-dev p7zip-full

# Enable 386 multilib toolchain if needed
ARG TARGET_ARCH
RUN if [ "$TARGET_ARCH" = "386" ]; then \
    dpkg --add-architecture i386 && \
    apt-get update -qq && \
    apt-get install -yq \
    gcc-multilib g++-multilib valgrind:i386 libssl-dev:i386 \
    libc6-dev:i386 libgcc-11-dev:i386 libstdc++-11-dev:i386 \
    libz-dev:i386 libyaml-dev:i386; \
    fi

WORKDIR /tmp/assets

ARG RUBY_VERSION
ENV RUBY_VERSION=${RUBY_VERSION}
ENV TARGET_ARCH=${TARGET_ARCH}

COPY ./assets/constants.sh /tmp/assets/constants.sh
COPY ./assets/compile-portable-ruby.sh /tmp/assets/compile-portable-ruby.sh
RUN bash /tmp/assets/compile-portable-ruby.sh

COPY ./assets/patch-portable-ruby.sh /tmp/assets/patch-portable-ruby.sh
RUN bash /tmp/assets/patch-portable-ruby.sh