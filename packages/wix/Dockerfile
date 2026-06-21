ARG PLATFORM=linux/amd64
FROM --platform=${PLATFORM} ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV WINEDEBUG=-all
# Shared prefix avoids redundant Wine initialization across test runs in the container.
ENV WINEPREFIX=/root/.wine

# Runtime notes for WiX v3:
#   candle.exe / light.exe are .NET Framework managed executables, so the Wine
#   prefix needs wine-mono (Wine's .NET Framework implementation). The structural
#   tests (file checks + wine sanity check) always pass. The full functional test
#   (candle → light → .msi) runs only on a native x86_64 host with wine-mono
#   installed; under CPU emulation (Rosetta/QEMU) it skips gracefully.
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

# Pre-stage wine-mono so `wineboot --init` installs the .NET Framework runtime
# offline. Ubuntu 24.04 ships wine 9.0, which expects wine-mono 9.0.0; placing
# the matching MSI in Wine's shared mono dir makes wineboot auto-install it.
ARG WINE_MONO_VERSION=9.0.0
ARG WINE_MONO_SHA256=79f6c43100675566c112f4199b9ea7b944d338164b34bd91fa11b0b0a414e1c4
RUN mkdir -p /usr/share/wine/mono && \
    curl -fsSL --retry 3 \
      "https://dl.winehq.org/wine/wine-mono/${WINE_MONO_VERSION}/wine-mono-${WINE_MONO_VERSION}-x86.msi" \
      -o "/usr/share/wine/mono/wine-mono-${WINE_MONO_VERSION}-x86.msi" && \
    echo "${WINE_MONO_SHA256}  /usr/share/wine/mono/wine-mono-${WINE_MONO_VERSION}-x86.msi" | sha256sum -c -

# Pre-initialize the Wine prefix at build time (installs wine-mono from the
# staged MSI) so the first `wine` call in the test doesn't pay the cost under
# the test timeout.
RUN /bin/bash -c ' \
    Xvfb :98 -screen 0 800x600x16 -nolisten tcp & XVFB_PID=$! && \
    sleep 2 && \
    DISPLAY=:98 wine wineboot --init 2>/dev/null || true && \
    wineserver -k 2>/dev/null || true && \
    kill "$XVFB_PID" 2>/dev/null || true \
'
