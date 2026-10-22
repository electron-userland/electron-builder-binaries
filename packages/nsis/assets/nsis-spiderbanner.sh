#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# SpiderBanner Plugin Builder (Docker-based)
# =============================================================================
# Compiles the SpiderBanner NSIS plugin (x86-unicode, x86-ansi and amd64-unicode)
# from source
# inside a Docker container, replacing the prebuilt DLLs previously downloaded
# from the NSIS wiki.
#
# Source: https://github.com/nsis-community/plugin-spiderbanner (the original
# NSIS wiki source, unmodified), pinned to a commit. The plugin API
# (pluginapi.c and headers) comes from the same NSIS branch as makensis.
#
# Does NOT download or merge with base bundle.
# Output: Single tar.gz with windows/Plugins/{x86-unicode,x86-ansi,amd64-unicode}/SpiderBanner.dll.
#
# Mirrors the structure of nsis-elevate.sh.
# =============================================================================

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
OUT_DIR="$BASE_DIR/out/nsis"

# Version configuration
NSIS_BRANCH=${NSIS_BRANCH_OR_COMMIT:-v312}

# SpiderBanner source (git commit SHA pins the exact content)
SPIDERBANNER_REPO="https://github.com/nsis-community/plugin-spiderbanner.git"
SPIDERBANNER_COMMIT="0395850e280b2877864835676fe6664427164aed"

# Docker configuration
IMAGE_TAG="${NSIS_BRANCH//\//_}"
IMAGE_NAME="nsis-spiderbanner-builder:${IMAGE_TAG}"
CONTAINER_NAME="nsis-spiderbanner-build-$$"

OUTPUT_ARCHIVE="$OUT_DIR/nsis-bundle-spiderbanner-$NSIS_BRANCH.tar.gz"

echo "🕷️  Building SpiderBanner plugin from source (Docker)..."
echo "   SpiderBanner commit: $SPIDERBANNER_COMMIT"
echo "   NSIS branch:         $NSIS_BRANCH"
echo ""

# =============================================================================
# Setup
# =============================================================================

mkdir -p "$OUT_DIR"

# =============================================================================
# Check Prerequisites
# =============================================================================

if ! command -v docker &> /dev/null; then
    echo "❌ Docker is required but not installed"
    echo "   Install Docker: https://docs.docker.com/get-docker/"
    exit 1
fi

# =============================================================================
# Cleanup Handler
# =============================================================================

cleanup() {
    echo ""
    echo "🧹 Cleaning up Docker resources..."
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
    [ -n "${DOCKERFILE:-}" ] && rm -f "$DOCKERFILE" 2>/dev/null || true
    [ -n "${TEMP_DIR:-}" ] && rm -rf "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# =============================================================================
# Create Dockerfile
# =============================================================================

echo "📝 Creating Dockerfile for SpiderBanner build..."

DOCKERFILE="$OUT_DIR/Dockerfile.spiderbanner"

cat > "$DOCKERFILE" <<'DOCKERFILE_END'
FROM ubuntu:22.04

ARG NSIS_BRANCH
ARG SPIDERBANNER_REPO
ARG SPIDERBANNER_COMMIT
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    ca-certificates \
    git \
    mingw-w64 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Fetch the plugin source at the pinned commit (the SHA verifies the content).
RUN git init -q spiderbanner && \
    git -C spiderbanner remote add origin "${SPIDERBANNER_REPO}" && \
    git -C spiderbanner fetch -q --depth=1 origin "${SPIDERBANNER_COMMIT}" && \
    git -C spiderbanner checkout -q FETCH_HEAD && \
    test "$(git -C spiderbanner rev-parse HEAD)" = "${SPIDERBANNER_COMMIT}"

# Fetch the NSIS plugin API from the same branch makensis is built from.
RUN git init -q nsis && \
    git -C nsis remote add origin https://github.com/NSIS-Dev/nsis.git && \
    git -C nsis fetch -q --depth=1 origin "${NSIS_BRANCH}" && \
    git -C nsis checkout -q FETCH_HEAD

# Assemble the sources. The plugin ships an older copy of the plugin API headers;
# use the current ones (with pluginapi.c) so the API matches this NSIS version.
# GCC does not normalise backslashes in #include paths, and MinGW has no MFC
# afxres.h, so patch those two lines (build fixes only, no behaviour change).
RUN mkdir -p src/nsis && \
    cp spiderbanner/Contrib/SpiderBanner/*.c \
       spiderbanner/Contrib/SpiderBanner/*.h \
       spiderbanner/Contrib/SpiderBanner/*.rc src/ && \
    cp nsis/Contrib/ExDLL/pluginapi.c \
       nsis/Contrib/ExDLL/pluginapi.h \
       nsis/Contrib/ExDLL/nsis_tchar.h \
       nsis/Source/exehead/api.h src/nsis/ && \
    sed -i 's|"nsis\\pluginapi.h"|"nsis/pluginapi.h"|' src/SpiderBanner.c && \
    sed -i 's|"afxres.h"|"winresrc.h"|' src/SpiderBanner.rc

# Variants: <NSIS plugin dir>:<MinGW toolchain prefix>:<entry symbol>:<defines>
# amd64-unicode is the folder NSIS uses for 64-bit installers (Target amd64-unicode);
# NSIS has no 64-bit ANSI target. The plugin defines its own _DllMainCRTStartup,
# mirroring how it was built with MSVC (no CRT); on x86 its stdcall name is decorated.
RUN printf '%s\n' \
      "x86-unicode:i686:__DllMainCRTStartup@12:-DUNICODE -D_UNICODE" \
      "x86-ansi:i686:__DllMainCRTStartup@12:" \
      "amd64-unicode:x86_64:_DllMainCRTStartup:-DUNICODE -D_UNICODE" \
    | while IFS=: read -r dir arch entry defs; do \
      mkdir -p "/output/$dir" && \
      "$arch-w64-mingw32-windres" -I src src/SpiderBanner.rc -O coff -o "src/SpiderBanner-res-$dir.o" && \
      "$arch-w64-mingw32-gcc" \
          $defs \
          -O2 -s -shared \
          -nostdlib "-Wl,-e,$entry" \
          -I src -I src/nsis \
          -o "/output/$dir/SpiderBanner.dll" \
          src/SpiderBanner.c src/ProgressClass.c src/nsis/pluginapi.c "src/SpiderBanner-res-$dir.o" \
          -lkernel32 -luser32 -lgdi32 -lmsvcrt \
          -lgcc || exit 1; \
      exports=$("$arch-w64-mingw32-objdump" -p "/output/$dir/SpiderBanner.dll"); \
      for fn in Show ShowPBOnly Destroy; do \
        echo "$exports" | grep -Eq "\] ${fn}\$" || { echo "$dir: export $fn missing"; exit 1; }; \
      done; \
    done
DOCKERFILE_END

# =============================================================================
# Build Docker Image
# =============================================================================

echo ""
echo "🔨 Building Docker image..."

docker build \
    --build-arg NSIS_BRANCH="$NSIS_BRANCH" \
    --build-arg SPIDERBANNER_REPO="$SPIDERBANNER_REPO" \
    --build-arg SPIDERBANNER_COMMIT="$SPIDERBANNER_COMMIT" \
    -t "$IMAGE_NAME" \
    - < "$DOCKERFILE"

echo "  ✓ Docker image built successfully"

# =============================================================================
# Extract Compiled Binaries
# =============================================================================

echo ""
echo "📦 Extracting compiled SpiderBanner.dll..."

docker create --name "$CONTAINER_NAME" "$IMAGE_NAME" /bin/true

TEMP_DIR="$OUT_DIR/temp-spiderbanner"
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR/nsis-bundle/windows/Plugins"

for variant in x86-unicode x86-ansi amd64-unicode; do
    docker cp "$CONTAINER_NAME:/output/$variant" "$TEMP_DIR/nsis-bundle/windows/Plugins/$variant"
    DLL="$TEMP_DIR/nsis-bundle/windows/Plugins/$variant/SpiderBanner.dll"

    if [ ! -f "$DLL" ]; then
        echo "❌ Failed to extract $variant/SpiderBanner.dll from container"
        exit 1
    fi

    # Verify Binary (PE MZ header)
    MZ=$(od -N 2 -A n -t x1 "$DLL" 2>/dev/null | tr -d ' \n')
    if [ "$MZ" = "4d5a" ]; then
        echo "  ✓ $variant/SpiderBanner.dll (valid PE, $(du -h "$DLL" | cut -f1))"
    else
        echo "  ❌ $variant/SpiderBanner.dll: not a valid PE (MZ header check failed)"
        exit 1
    fi
done

# =============================================================================
# Create Archive
# =============================================================================

echo ""
echo "📦 Creating SpiderBanner bundle archive..."

cd "$TEMP_DIR"
tar -czf "${OUTPUT_ARCHIVE}" nsis-bundle

# =============================================================================
# Cleanup
# =============================================================================

rm -f "$DOCKERFILE"
rm -rf "$TEMP_DIR"

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "================================================================"
echo "  ✅ SpiderBanner Build Complete!"
echo "================================================================"
echo "  📁 Archive: $OUTPUT_ARCHIVE"
echo "  📊 Size:    $(du -h "$OUTPUT_ARCHIVE" | cut -f1)"
echo "================================================================"
echo ""
