# syntax=docker/dockerfile:1.4

ARG TARGET_ARCH=x86_64
ARG PLATFORM_ARCH
ARG RUBY_VERSION=3.4.3

FROM --platform=linux/${PLATFORM_ARCH:-amd64} debian:buster

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    build-essential \
    libssl-dev \
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

COPY ./assets/constants.sh /tmp/assets/constants.sh
COPY ./assets/compile-portable-ruby.sh /tmp/assets/compile-portable-ruby.sh
RUN bash /tmp/assets/compile-portable-ruby.sh

COPY ./assets/patch-portable-ruby.sh /tmp/assets/patch-portable-ruby.sh
RUN bash /tmp/assets/patch-portable-ruby.sh