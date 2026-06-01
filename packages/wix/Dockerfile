ARG PLATFORM=linux/amd64
FROM --platform=${PLATFORM} ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV WINEDEBUG=-all
# Shared prefix avoids redundant Wine initialization across test runs in the container.
ENV WINEPREFIX=/root/.wine

# Runtime notes for WiX v4:
#   wix.exe targets net6.0 and requires the .NET 6 Windows runtime in the Wine prefix.
#   The structural tests (file checks + wine sanity check) always pass.
#   For the full functional test (wix.exe build → .msi), install .NET 6 in the prefix:
#     winetricks dotnet60   (or dotnet80 — wix.exe accepts any rollforward Major runtime)
#
# wine32:i386 — WoW64 support for 32-bit auxiliary executables
# xvfb        — virtual display so Wine's GUI subsystem initialises headlessly

RUN dpkg --add-architecture i386 && \
    apt-get update && apt-get install -y --no-install-recommends \
    curl \
    unzip \
    rsync \
    wine \
    wine32:i386 \
    xxd \
    ca-certificates \
    xz-utils \
    xvfb \
    && rm -rf /var/lib/apt/lists/*

# Pre-initialize the Wine prefix at build time so the first `wine` call in
# the test doesn't pay the initialization cost under the test timeout.
RUN /bin/bash -c ' \
    Xvfb :98 -screen 0 800x600x16 -nolisten tcp & XVFB_PID=$! && \
    sleep 2 && \
    DISPLAY=:98 wine wineboot --init 2>/dev/null || true && \
    wineserver -k 2>/dev/null || true && \
    kill "$XVFB_PID" 2>/dev/null || true \
'
