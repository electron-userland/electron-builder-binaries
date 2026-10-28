# syntax=docker/dockerfile:1.4

ARG TARGET_ARCH=x86_64
ARG PLATFORM_ARCH
ARG RUBY_VERSION=3.4.12

FROM --platform=linux/${PLATFORM_ARCH:-amd64} debian:buster

ENV DEBIAN_FRONTEND=noninteractive
RUN sed -i 's|http://deb.debian.org/debian|http://archive.debian.org/debian|g' /etc/apt/sources.list \
    && echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid-until \
    && apt-get update && apt-get install -y \
    build-essential \
    libreadline-dev \
    zlib1g-dev \
    libyaml-dev \
    libffi-dev \
    libgdbm-dev \
    libncurses5-dev \
    curl \
    git \
    autoconf \
    bison \
    pkg-config \
    patchelf \
    ruby-dev \
    openssl \
    p7zip-full \
    xz-utils

WORKDIR /tmp/assets

ARG RUBY_VERSION
ENV RUBY_VERSION=${RUBY_VERSION}

ARG TARGET_ARCH
ENV TARGET_ARCH=${TARGET_ARCH}

# Static OpenSSL 3.5 LTS replaces buster's EOL libssl1.1 (libssl-dev is not installed,
# so Ruby's openssl extension can only find this build).
ENV OPENSSL_PREFIX=/opt/openssl
COPY ./assets/compile-openssl.sh /tmp/assets/compile-openssl.sh
RUN bash /tmp/assets/compile-openssl.sh

COPY ./assets/constants.sh /tmp/assets/constants.sh
COPY ./assets/compile-portable-ruby.sh /tmp/assets/compile-portable-ruby.sh
RUN bash /tmp/assets/compile-portable-ruby.sh

COPY ./assets/patch-portable-ruby.sh /tmp/assets/patch-portable-ruby.sh
RUN bash /tmp/assets/patch-portable-ruby.sh