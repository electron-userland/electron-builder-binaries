#!/usr/bin/env bash
set -euo pipefail

WINE_VERSION=${WINE_VERSION:-11.0}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="${ROOT_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
BUILD_DIR=${BUILD_DIR:-$ROOT_DIR/build}

# NOTE: update the checksums here as new versions are added
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
  --enable-win64
  --without-x
  --without-cups
  --without-dbus
  --without-freetype
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

# Wine 9+ with --enable-win64 no longer installs a separate wine64 binary.
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
# 🔒 KEEP LIB/WINE PE DLLS (builtin loader requirement)
############################################

# DO NOT remove lib/wine/${PLATFORM_ARCH}-windows/.
# These are Wine's *builtin* PE DLLs. At runtime Wine loads builtin modules
# (ntdll, kernel32, win32u, ...) as PE images from this dlldir and pairs each
# with its unix counterpart in lib/wine/${PLATFORM_ARCH}-unix/. The copies that
# wineboot --init writes into the prefix's system32 are placeholders, NOT the
# code Wine executes — so a pre-initialized prefix is not a substitute.
# Removing this directory makes every process fail to bootstrap with
# STATUS_DLL_NOT_FOUND (c0000135): "failed to load .../x86_64-unix/ntdll.dll".
echo "🔒 Keeping lib/wine/${PLATFORM_ARCH}-windows (required builtin PE DLLs)"

############################################
# 🧹 PRUNE system32 — whitelist-based
############################################

echo "🧹 Pruning system32 to whitelist"
SYSTEM32_DIR="$WINEPREFIX/drive_c/windows/system32"

# DLLs sufficient for electron-builder tools (rcedit + WiX candle/light).
# Derived from: CI baseline (32 DLLs that make install produced on x86_64)
# plus rcedit loaddll trace. Removing everything else saves ~500 MB.
SYSTEM32_KEEP_DLLS="
  advapi32.dll bcrypt.dll combase.dll comctl32.dll comdlg32.dll coml2.dll
  crypt32.dll cryptbase.dll cryptui.dll gdi32.dll imm32.dll kernel32.dll
  kernelbase.dll mpr.dll msvcrt.dll ncrypt.dll ntdll.dll ole32.dll
  oleaut32.dll rpcrt4.dll sechost.dll shcore.dll shell32.dll shlwapi.dll
  ucrtbase.dll urlmon.dll user32.dll version.dll win32u.dll wininet.dll
  ws2_32.dll xmllite.dll
"
for _dll in "$SYSTEM32_DIR"/*.dll; do
    [ -f "$_dll" ] || continue
    _name=$(basename "$_dll")
    case " $SYSTEM32_KEEP_DLLS " in
        *" $_name "*) ;;
        *) rm -f "$_dll" ;;
    esac
done

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

rm -rf \
  "$WINDOWS_DIR/Installer" \
  "$WINDOWS_DIR/Microsoft.NET" \
  "$WINDOWS_DIR/mono" \
  "$WINDOWS_DIR/syswow64" \
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
