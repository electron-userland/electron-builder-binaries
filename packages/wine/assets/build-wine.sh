#!/usr/bin/env bash
set -euo pipefail

WINE_VERSION=${WINE_VERSION:-11.0}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="${ROOT_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
BUILD_DIR=${BUILD_DIR:-$ROOT_DIR/build}

# NOTE: update the checksum here as new Wine versions are added.
get_checksum() {
    case "$1" in
        11.0) echo "c07a6857933c1fc60dff5448d79f39c92481c1e9db5aa628db9d0358446e0701" ;;
        *) exit 1 ;;
    esac
}

PLATFORM_ARCH="x86_64"
OS_TARGET="${OS_TARGET:-$(uname -s | tr '[:upper:]' '[:lower:]')}"
HOST_ARCH=$(arch)

IS_DARWIN=false
if [ "$OS_TARGET" = "darwin" ]; then
  IS_DARWIN=true
fi

if $IS_DARWIN; then
    echo "🍺 Ensuring Homebrew dependencies (brew bundle)"

    if ! command -v brew >/dev/null 2>&1; then
        echo "❌ Homebrew not found"
        exit 1
    fi

    if [ ! -f "$SCRIPT_DIR/Brewfile" ]; then
        echo "❌ Brewfile not found"
        exit 1
    fi

    (
        cd "$SCRIPT_DIR"
        if ! brew bundle check; then
            echo "📦 Installing missing dependencies"
            brew bundle install
        else
            echo "🍻 Brewfile dependencies already satisfied"
        fi
    )

    BREW_PREFIX="$(brew --prefix)"
    export PATH="$BREW_PREFIX/opt/bison/bin:$PATH"
    export PATH="$BREW_PREFIX/opt/flex/bin:$PATH"
    export PATH="$BREW_PREFIX/opt/make/libexec/gnubin:$PATH"
    export PKG_CONFIG_PATH="$BREW_PREFIX/x86_64-w64-mingw32/lib/pkgconfig:${PKG_CONFIG_PATH:-$BREW_PREFIX/lib/pkgconfig}"

    # Sanity checks (fail fast)
    bison --version | grep -E '3\.' >/dev/null || {
        echo "❌ Wrong bison in PATH"
        which bison
        bison --version
        exit 1
    }

    if [ "$HOST_ARCH" = 'arm64' ]; then
        echo "🔄 ARM64 host — will cross-compile x86_64 Wine via -arch x86_64"
        export SDKROOT="$(xcode-select -p)/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    fi
fi

CHECKSUM=$(get_checksum "$WINE_VERSION")
WINE_MAJOR=$(echo "$WINE_VERSION" | cut -d. -f1)
WINE_URL="https://dl.winehq.org/wine/source/${WINE_MAJOR}.0/wine-${WINE_VERSION}.tar.xz"

DOWNLOAD_DIR="$BUILD_DIR/downloads"
SOURCE_DIR="$BUILD_DIR/wine-${WINE_VERSION}"
BUILD_WINE_DIR="$BUILD_DIR/wine64-build"
STAGE_DIR="$BUILD_DIR/wine-stage"
OUTPUT_DIR="$BUILD_DIR/wine-${WINE_VERSION}-${OS_TARGET}-${PLATFORM_ARCH}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/out}"

mkdir -p "$DOWNLOAD_DIR"

# Capture stdout to a log file; on failure print the tail so CI logs stay readable.
run_quiet() {
    local label="$1"; shift
    local log="$BUILD_DIR/${label// /_}.log"
    echo "⏳ ${label}..."
    if ! "$@" > "$log" 2>&1; then
        echo "❌ ${label} FAILED — last 50 lines:"
        tail -n 50 "$log" >&2
        exit 1
    fi
    echo "✅ ${label} done"
}

# Download and verify archive
ARCHIVE="$DOWNLOAD_DIR/wine-${WINE_VERSION}.tar.xz"
if [ ! -f "$ARCHIVE" ]; then
    echo "📥 Downloading Wine ${WINE_VERSION}..."
    curl -fSL --retry 3 --retry-delay 5 --max-time 1800 --progress-bar -o "$ARCHIVE" "$WINE_URL"

    if [ -n "$CHECKSUM" ]; then
        ACTUAL=$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')
        if [ "$ACTUAL" != "$CHECKSUM" ]; then
            echo "❌ Checksum failed: expected $CHECKSUM, got $ACTUAL"
            exit 1
        fi
        echo "✅ Verified"
    fi
fi

# Extract source
if [ ! -d "$SOURCE_DIR" ]; then
    echo "📂 Extracting..."
    tar -xJf "$ARCHIVE" -C "$BUILD_DIR"
fi

CONFIGURE_FLAGS=(
  --prefix="$STAGE_DIR"
  # 64-bit Wine that ALSO builds the i386 PE DLLs (new WoW64), matching the proven macos-wine-build
  # reference (--enable-win64 + --enable-archs=i386,x86_64). The native Windows tools this bundle runs
  # are 32-bit (Squirrel's WriteZipToSetup, the generated NSIS installer), so without the i386 arch
  # every 32-bit process dies with c0000135 (missing lib/wine/i386-windows/ntdll.dll). On Linux/Intel
  # x86_64 the CPU runs 32-bit natively.
  --enable-win64
  --enable-archs=i386,x86_64
  # Drop every external binding these native tools never touch. This shrinks the build and — the real
  # win — removes the matching host .so dependencies, so the bundle doesn't require
  # GStreamer/Vulkan/X/PulseAudio/etc. on the end user's machine. Kept (not listed): mingw (PE
  # compilation) and gnutls (TLS).
  --without-x          --without-wayland
  --without-opengl     --without-vulkan      --without-opencl
  --without-gstreamer  --without-ffmpeg
  --without-alsa       --without-oss         --without-pulse      --without-coreaudio
  --without-cups       --without-dbus        --without-udev
  --without-freetype   --without-fontconfig
  --without-sane       --without-gphoto      --without-usb        --without-v4l2
  --without-capi       --without-pcap        --without-pcsclite
  --without-krb5       --without-gssapi      --without-netapi
  --without-hwloc      --without-sdl
  --without-inotify    --without-gettextpo
)

NCPU=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

# On ARM64 macOS, run configure+make via Rosetta so uname -m returns x86_64.
# Wine then detects x86_64, uses x86_64-w64-mingw32-gcc (Homebrew mingw-w64) for PE DLLs,
# and compiles x86_64 Wine binaries that run via Rosetta on this machine.
# /usr/bin/make is a universal binary — arch -x86_64 /usr/bin/make works; Homebrew's make is not.
if $IS_DARWIN && [ "$HOST_ARCH" = 'arm64' ]; then
    CONFIGURE_CMD=(arch -x86_64 "$SOURCE_DIR/configure")
    MAKE_CMD=(arch -x86_64 /usr/bin/make)
else
    CONFIGURE_CMD=("$SOURCE_DIR/configure")
    MAKE_CMD=(make)
fi

rm -rf "$BUILD_WINE_DIR" "$STAGE_DIR"
mkdir -p "$BUILD_WINE_DIR" "$STAGE_DIR"
cd "$BUILD_WINE_DIR"

run_quiet "configure" "${CONFIGURE_CMD[@]}" "${CONFIGURE_FLAGS[@]}"

if [ "$OS_TARGET" = "darwin" ]; then
    bash "$SCRIPT_DIR/generate-brewfile.sh" "$BUILD_WINE_DIR/config.log"
fi

run_quiet "make -j${NCPU}" "${MAKE_CMD[@]}" -j"$NCPU"

# make install must NOT run under arch -x86_64 on ARM64 Mac.
# Homebrew's x86_64-w64-mingw32-strip is an ARM64 binary; under Rosetta it
# fails with "Bad CPU type", silently skipping PE DLL installation for DLLs
# that need winebuild --builtin processing (wintrust, setupapi, etc.).
# Running install natively lets that ARM64 strip tool work while winebuild
# (x86_64) is transparently handled by Rosetta.
if $IS_DARWIN && [ "$HOST_ARCH" = 'arm64' ]; then
    run_quiet "make install" /usr/bin/make install
else
    run_quiet "make install" "${MAKE_CMD[@]}" install
fi

cd "$ROOT_DIR"

# Wine 9+ (win64 / new WoW64) no longer installs a separate wine64 binary.
# Add wine64 → wine symlink for electron-builder compatibility.
if [ ! -e "$STAGE_DIR/bin/wine64" ] && [ -f "$STAGE_DIR/bin/wine" ]; then
    ln -s wine "$STAGE_DIR/bin/wine64"
    echo "🔗 Created wine64 → wine symlink"
fi

# Remove docs, headers, and unused share content
rm -rf "$STAGE_DIR/share/man" "$STAGE_DIR/share/doc" "$STAGE_DIR/share/gtk-doc" \
       "$STAGE_DIR/include" "$STAGE_DIR/share/applications"

# Adjust RPATHs for all binaries (macOS only — otool/install_name_tool are macOS-specific)
if $IS_DARWIN; then
    add_rpath_if_missing() {
        local binary="$1"
        local rpath="$2"

        if otool -l "$binary" | grep -A2 LC_RPATH | grep -q "$rpath"; then
            return 0
        fi

        install_name_tool -add_rpath "$rpath" "$binary"
    }

    for binary in wine64 wine wineserver wineboot winecfg; do
        binary_path="$STAGE_DIR/bin/$binary"
        [ -f "$binary_path" ] && add_rpath_if_missing "$binary_path" "@executable_path/../lib"
    done
fi

# Patch RPATH for Linux ELF binaries so wine can dlopen its own bundled libs
# from lib/ without needing LD_LIBRARY_PATH in the runtime environment.
# $ORIGIN is resolved by the Linux runtime linker relative to the binary's location,
# so $ORIGIN/../lib points to the sibling lib/ directory inside the toolset bundle.
if ! $IS_DARWIN; then
    if ! command -v patchelf >/dev/null 2>&1; then
        echo "❌ patchelf not found — install it (e.g. apt-get install -y patchelf)"
        exit 1
    fi
    for binary in wine wineserver wineboot; do
        binary_path="$STAGE_DIR/bin/$binary"
        if [ -f "$binary_path" ]; then
            patchelf --set-rpath '$ORIGIN/../lib' "$binary_path"
            echo "🔧 Patched RPATH on $(basename "$binary_path")"
        fi
    done
fi

############################################
# 🍇 INITIALIZE WINE PREFIX
############################################

echo "🍇 Initializing Wine prefix..."
export WINEPREFIX="$STAGE_DIR/wine-home"
export WINEARCH=win64
export WINEDEBUG=-all
if $IS_DARWIN; then
    # Headless: use the null display driver instead of winemac.drv so prefix
    # init never blocks on the macOS WindowServer on CI runners.
    export WINEDLLOVERRIDES="winemac.drv="
fi

# No .NET runtime is provisioned. electron-builder only runs NATIVE Windows tools under this bundle's
# Wine — rcedit, Squirrel's WriteZipToSetup.exe, and the generated NSIS installer (for uninstaller
# generation). The .NET-under-Wine paths (WiX candle/light for MSI, Windows PowerShell for Azure
# Trusted Signing) need real .NET Framework (dotnet462), not Wine Mono, and are out of scope here;
# Squirrel's own .NET tools (nuget/SyncReleases/Squirrel-Mono) run under the HOST's mono, not Wine.

if $IS_DARWIN; then
    "$STAGE_DIR/bin/wineboot" --init
    sleep 2
else
    # Built with --without-x: Wine uses a null display driver and doesn't require X11.
    # Start Xvfb if available for belt-and-suspenders; fall back to headless if not.
    if command -v Xvfb >/dev/null 2>&1; then
        Xvfb :99 -screen 0 1024x768x24 &
        XVFB_PID=$!
        trap "kill $XVFB_PID 2>/dev/null || true" EXIT
        sleep 2
        DISPLAY=:99 "$STAGE_DIR/bin/wineboot" --init || true
        sleep 2
    else
        DISPLAY= "$STAGE_DIR/bin/wineboot" --init || true
        sleep 2
    fi
fi

############################################
# 🧪 RETRACE (opt-in, container only) — regenerate the committed keep-list
############################################

# Refresh wine-keep-dlls.txt by tracing the real native tools under THIS freshly-built — still
# un-pruned — Wine. This downloads and executes AV-flagged Windows tooling, so it is opt-in
# (RETRACE=1) and meant to run INSIDE the Linux build container, never on a developer's machine.
# generate-trace-exes.sh rewrites the list next to itself (where the prune below reads it); we also
# copy it to $OUT_DIR so it can be retrieved from the mounted /output volume and committed:
#   docker run --rm --platform linux/amd64 -e RETRACE=1 -e OUT_DIR=/output \
#       -v "$PWD/refresh:/output" wine-builder-linux
#   cp refresh/wine-keep-dlls.txt packages/wine/assets/   # then git add + commit
if [ -n "${RETRACE:-}" ]; then
    echo "🧪 RETRACE=1 — regenerating keep-list by tracing tools under the new Wine..."
    WINE_BIN="$STAGE_DIR/bin/wine" WINEPREFIX="$WINEPREFIX" \
        bash "$SCRIPT_DIR/generate-trace-exes.sh" "$BUILD_DIR/trace-tools"
    mkdir -p "$OUT_DIR"
    cp "$SCRIPT_DIR/wine-keep-dlls.txt" "$OUT_DIR/" 2>/dev/null || true
    echo "📄 Regenerated keep-list copied to $OUT_DIR — commit wine-keep-dlls.txt into packages/wine/assets/"
fi

############################################
# 🧹 PRUNE PE DLLS — whitelist-based (system32 prefix + lib/wine builtin dlldirs)
############################################

# Wine's *builtin* PE DLLs live in lib/wine/${arch}-windows/ (paired with their unix
# counterpart in lib/wine/${arch}-unix/). The new WoW64 loader executes those builtin
# images directly — the copies wineboot writes into the prefix's system32 are not a
# substitute, so removing lib/wine/${arch}-windows makes every process fail to bootstrap
# with STATUS_DLL_NOT_FOUND (c0000135): "failed to load .../x86_64-unix/ntdll.dll".
#
# Keeping ALL of them is ~770 MB though, so instead we keep only the DLLs the bundled
# tools actually load and apply the same whitelist to BOTH the prefix system32 and the
# lib/wine builtin dlldirs (x86_64-windows for the 64-bit host, i386-windows for the
# 32-bit WoW64 guest — Squirrel's WriteZipToSetup and the NSIS installer are 32-bit).
#
# The keep-list is a committed, generated artifact — wine-keep-dlls.txt, next to this script. It is
# produced by assets/generate-trace-exes.sh (which downloads + runs the bundled Windows tools under
# Wine and records the system DLLs they load) and refreshed deliberately on a Wine/tool bump. The
# build only READS it — it never downloads or executes that (AV-flagged) tooling. We union it with a
# small bootstrap floor: the DLLs the loader maps to start any process, kept regardless so Wine boots
# even if the list is ever edited down too far.
BOOTSTRAP_KEEP_DLLS="
  ntdll.dll kernel32.dll kernelbase.dll win32u.dll wow64.dll wow64cpu.dll
  wow64win.dll sechost.dll ucrtbase.dll msvcrt.dll rpcrt4.dll advapi32.dll
  user32.dll gdi32.dll ole32.dll combase.dll
"
KEEP_FILE="$SCRIPT_DIR/wine-keep-dlls.txt"
if [ ! -s "$KEEP_FILE" ]; then
    echo "❌ missing PE DLL keep-list: $KEEP_FILE — regenerate it with assets/generate-trace-exes.sh"
    exit 1
fi
echo "📄 Using committed PE DLL keep-list: $KEEP_FILE"
FILE_KEEP_DLLS="$(grep -vE '^[[:space:]]*#' "$KEEP_FILE")"
# Collapse newlines + indentation to single spaces so the space-delimited case match below works.
WINDOWS_KEEP_DLLS=$(echo $BOOTSTRAP_KEEP_DLLS $FILE_KEEP_DLLS)
echo "  Keeping $(printf '%s\n' $WINDOWS_KEEP_DLLS | sort -u | wc -l | tr -d ' ') unique PE DLLs"

prune_dlls_to_whitelist() {
    _dir="$1"
    [ -d "$_dir" ] || return 0
    for _dll in "$_dir"/*.dll; do
        [ -f "$_dll" ] || continue
        _name=$(basename "$_dll")
        case " $WINDOWS_KEEP_DLLS " in
            *" $_name "*) ;;
            *) rm -f "$_dll" ;;
        esac
    done
}

echo "🧹 Pruning PE DLLs to whitelist (system32 + syswow64 + lib/wine builtin dlldirs)"
SYSTEM32_DIR="$WINEPREFIX/drive_c/windows/system32"
prune_dlls_to_whitelist "$SYSTEM32_DIR"
prune_dlls_to_whitelist "$WINEPREFIX/drive_c/windows/syswow64"
prune_dlls_to_whitelist "$STAGE_DIR/lib/wine/${PLATFORM_ARCH}-windows"
prune_dlls_to_whitelist "$STAGE_DIR/lib/wine/i386-windows"

# EXEs: keep only wine's internal service processes; drop all user-visible tools
SYSTEM32_KEEP_EXES="
  conhost.exe plugplay.exe rpcss.exe services.exe start.exe
  svchost.exe wineboot.exe winedevice.exe
"
for _exe in "$SYSTEM32_DIR"/*.exe; do
    [ -f "$_exe" ] || continue
    _name=$(basename "$_exe")
    case " $SYSTEM32_KEEP_EXES " in
        *" $_name "*) ;;
        *) rm -f "$_exe" ;;
    esac
done

# Non-essential file types
rm -f "$SYSTEM32_DIR"/*.cpl "$SYSTEM32_DIR"/*.tlb "$SYSTEM32_DIR"/*.ocx \
      "$SYSTEM32_DIR"/*.drv "$SYSTEM32_DIR"/*.ax  "$SYSTEM32_DIR"/*.acm

############################################
# 🧹 REMOVE BULK WINDOWS CONTENT
############################################

echo "🧹 Removing Windows bulk"
WINDOWS_DIR="$WINEPREFIX/drive_c/windows"

# No .NET in this bundle: drop the Microsoft.NET Framework tree AND any Wine Mono dir. wineboot won't
# install Mono without a datadir .msi (we provision none), but remove it defensively. syswow64 is
# pruned above, not removed.
rm -rf \
  "$WINDOWS_DIR/Installer" \
  "$WINDOWS_DIR/Microsoft.NET" \
  "$WINDOWS_DIR/mono" \
  "$WINDOWS_DIR/logs" \
  "$WINDOWS_DIR/inf" \
  "$WINDOWS_DIR/Temp" \
  "$WINDOWS_DIR/system32/gecko" \
  "$WINDOWS_DIR/winsxs" \
  "$WINDOWS_DIR/resources" \
  "$WINDOWS_DIR/globalization"

rm -f \
  "$WINDOWS_DIR/notepad.exe" \
  "$WINDOWS_DIR/regedit.exe" \
  "$WINDOWS_DIR/explorer.exe" \
  "$WINDOWS_DIR/hh.exe"

############################################
# 🪓 PRUNE DEV TOOLS FROM bin/
############################################

echo "🪓 Removing Wine development tools from bin/"
rm -f \
  "$STAGE_DIR/bin/widl" \
  "$STAGE_DIR/bin/winebuild" \
  "$STAGE_DIR/bin/winedump" \
  "$STAGE_DIR/bin/winegcc" \
  "$STAGE_DIR/bin/winecpp" \
  "$STAGE_DIR/bin/wineg++" \
  "$STAGE_DIR/bin/winemaker" \
  "$STAGE_DIR/bin/wmc" \
  "$STAGE_DIR/bin/wrc" \
  "$STAGE_DIR/bin/function_grep.pl"

############################################
# 🪓 STRIP BINARIES
############################################

echo "🪓 Stripping binaries"
find "$STAGE_DIR/bin" "$STAGE_DIR/lib" -type f -perm +111 -exec strip -x {} \; 2>/dev/null || true

############################################
# 📦 PACKAGE
############################################

echo "📦 Packaging archive"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR" "$OUT_DIR"
cp -R "$STAGE_DIR/"* "$OUTPUT_DIR/"

OUT_ARCHIVE="$OUT_DIR/wine-${WINE_VERSION}-${OS_TARGET}-${PLATFORM_ARCH}.tar.xz"
tar -C "$BUILD_DIR" -cJf "$OUT_ARCHIVE" "$(basename "$OUTPUT_DIR")"

echo "✅ DONE"
du -sh "$OUT_ARCHIVE"
