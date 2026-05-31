ARG PLATFORM=linux/amd64
FROM --platform=${PLATFORM} ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV WINEDEBUG=-all
# Use a fixed global prefix that is pre-initialized during image build,
# so tests never hit the mono-installation stall at runtime.
ENV WINEPREFIX=/root/.wine

# WiX v3 tools are .NET Framework 3.5 assemblies. We need:
#   - wine32:i386  for 32-bit WoW64 support inside Wine
#   - xvfb         virtual display for Wine's GUI subsystem (needed even for CLI apps)
#   - wine-mono    .NET runtime — pre-installed at build time to avoid a dialog at run time
ARG WINE_MONO_VERSION=9.0.0

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

# Cache the wine-mono MSI so Wine can install it without hitting the network.
RUN mkdir -p /root/.cache/wine && \
    curl -fsSL \
    "https://dl.winehq.org/wine/wine-mono/${WINE_MONO_VERSION}/wine-mono-${WINE_MONO_VERSION}-x86.msi" \
    -o "/root/.cache/wine/wine-mono-${WINE_MONO_VERSION}-x86.msi"

# Pre-initialize the Wine prefix and install Mono now, so test runs don't block.
# We start a temporary Xvfb display so Wine's GUI components can initialize headlessly.
RUN /bin/bash -c ' \
    Xvfb :98 -screen 0 800x600x16 -nolisten tcp & XVFB_PID=$! && \
    sleep 2 && \
    DISPLAY=:98 wine wineboot --init 2>/dev/null && \
    DISPLAY=:98 wine msiexec /i "/root/.cache/wine/wine-mono-9.0.0-x86.msi" \
        MONO_SILENT_INSTALL=1 /quiet /norestart 2>/dev/null && \
    wineserver -k 2>/dev/null || true && \
    kill "$XVFB_PID" 2>/dev/null || true \
'
