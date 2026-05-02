#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "❌ Must be run on macOS"
    exit 1
fi

### ================================
### CONFIG
### ================================
_DEFAULT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT=""
OUTPUT_DIR=""
PYTHON_VERSION=""
DMGBUILD_VERSION=""
CODESIGN_IDENTITY="-"
ARCH=""

usage() {
    echo "Usage: $0 --root <dir> --output-dir <dir> --python-version <ver> --dmgbuild-version <ver> [--codesign-identity <id>] [--arch <arm64|x86_64>]"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)              ROOT="$2";              shift 2 ;;
        --output-dir)        OUTPUT_DIR="$2";        shift 2 ;;
        --python-version)    PYTHON_VERSION="$2";    shift 2 ;;
        --dmgbuild-version)  DMGBUILD_VERSION="$2";  shift 2 ;;
        --codesign-identity) CODESIGN_IDENTITY="$2"; shift 2 ;;
        --arch)              ARCH="$2";              shift 2 ;;
        *) echo "Unknown argument: $1"; usage ;;
    esac
done

ROOT="${ROOT:-$_DEFAULT_ROOT}"
OUTPUT_DIR="${OUTPUT_DIR:-${ROOT}/dist}"
PYTHON_VERSION="${PYTHON_VERSION:-3.11.8}"
DMGBUILD_VERSION="${DMGBUILD_VERSION:-1.6.6}"
ARCH="${ARCH:-$(uname -m)}"

if [[ "$ARCH" != "arm64" && "$ARCH" != "x86_64" ]]; then
    echo "❌ Unsupported ARCH: $ARCH"
    exit 1
fi

run_arch() {
    if [[ "$ARCH" == "x86_64" && "$(uname -m)" == "arm64" ]]; then
        arch -x86_64 "$@"
    else
        "$@"
    fi
}

export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-11.0}"
BUILD_DIR="${ROOT}/build"
SRC_DIR="$BUILD_DIR/src"
TEST_DIR="$BUILD_DIR/test"
PREFIX="$BUILD_DIR/python"
DIR_TO_ARCHIVE="${BUILD_DIR}/dmg-builder-${ARCH}-${DMGBUILD_VERSION}"

echo "🐍 dmgbuild portable bundler"
echo "📁 Output directory: ${DIR_TO_ARCHIVE}"
echo "🔢 Python version: ${PYTHON_VERSION}"
echo "📦 dmgbuild version: ${DMGBUILD_VERSION}"
echo "🍎 macOS deployment target: ${MACOSX_DEPLOYMENT_TARGET}"
echo ""

### ================================
### CLEAN
### ================================
rm -rf "$BUILD_DIR"
mkdir -p "$SRC_DIR" "$PREFIX" "$TEST_DIR" "$DIR_TO_ARCHIVE"

## ================================
## FETCH PYTHON
## ================================
cd "$SRC_DIR"
curl -LO https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz
tar xf Python-${PYTHON_VERSION}.tgz
cd Python-${PYTHON_VERSION}

### ================================
### BUILD ENV (NO HOMEBREW)
### ================================
# Pin to the Xcode SDK so headers/libs come from the SDK only and never from /usr/local (Intel runners) or /opt/homebrew (Apple-silicon runners). 
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
export SDKROOT
export CC=clang
export CXX=clang++
export CFLAGS="-O3 -fPIC -arch ${ARCH} -isysroot ${SDKROOT} -mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET}"
export LDFLAGS="-arch ${ARCH} -isysroot ${SDKROOT} -mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET}"
# Belt-and-braces: tell ld(64) explicitly NOT to search Homebrew prefixes.
export LIBRARY_PATH=""
export CPATH=""

unset PKG_CONFIG_PATH

# Locate Homebrew OpenSSL. --with-openssl scopes it only to the _ssl extension module, so no other Homebrew library can bleed into the build.
OPENSSL_PREFIX=""
for candidate in \
    "$(brew --prefix openssl@3 2>/dev/null || true)" \
    /opt/homebrew/opt/openssl@3 \
    /usr/local/opt/openssl@3 \
    /opt/homebrew/opt/openssl \
    /usr/local/opt/openssl; do
  if [[ -n "$candidate" && -d "$candidate/include/openssl" ]]; then
    OPENSSL_PREFIX="$candidate"
    break
  fi
done
if [[ -z "$OPENSSL_PREFIX" ]]; then
  echo "❌ OpenSSL not found — install it with: brew install openssl@3"
  exit 1
fi
echo "🔐 Using OpenSSL at: $OPENSSL_PREFIX"

### ================================
### CONFIGURE
### ================================
# Force the autoconf cache for libintl/gettext detection to "no" so that# even if a stray /usr/local or /opt/homebrew gettext slipped onto the search path, _locale would not link against it. macOS already has everything _locale needs in libSystem
run_arch ./configure \
  --prefix="$PREFIX" \
  --enable-optimizations \
  --disable-shared \
  --disable-test-modules \
  --with-openssl="$OPENSSL_PREFIX" \
  ac_cv_header_libintl_h=no \
  ac_cv_lib_intl_textdomain=no \
  ac_cv_lib_intl_libintl_setlocale=no

### ================================
### BUILD & INSTALL
### ================================
JOBS="$(sysctl -n hw.ncpu)"
run_arch make -j"$JOBS"
run_arch make install
file "$PREFIX/bin/python3"

### ================================
### INSTALL REQUIRED TOOLS
### ================================
echo "🐍 Installing pip and dmgbuild"

run_arch "$PREFIX/bin/python3" -m pip install --upgrade pip --no-warn-script-location --no-cache
run_arch "$PREFIX/bin/python3" -m pip install --no-warn-script-location --no-cache "dmgbuild[badge_icons] @ git+https://github.com/dmgbuild/dmgbuild.git@${DMGBUILD_VERSION}"

###############################################################################
# ADD VERSION.txt FILE with python version and versions of each major package
###############################################################################
echo "📝 Creating VERSION.txt…"
{
    echo "dmgbuild version/commit hash: ${DMGBUILD_VERSION}"
    echo "Python version: ${PYTHON_VERSION}"
    echo "macOS deployment target: ${MACOSX_DEPLOYMENT_TARGET}"
    echo -n "dmgbuild package version: "
    run_arch "$PREFIX/bin/python3" -m pip show dmgbuild | grep ^Version: | awk '{print $2}'
} > "$DIR_TO_ARCHIVE/VERSION.txt"

###############################################################################
# MINIMAL SIZE REDUCTION
###############################################################################

test_dmgbuild() {
    run_arch "$PREFIX/bin/python3" -c "
import dmgbuild
import ds_store
import mac_alias
print('✓ All imports successful')
    " && \
    run_arch "$PREFIX/bin/python3" -m dmgbuild --help >/dev/null && \
    echo "✅ dmgbuild works" || \
    ( echo "❌ dmgbuild broken" && exit 1 )
}

PYTHON_LIB_DIR=$(find "$PREFIX/lib" -maxdepth 1 -type d -name "python3.*" | head -n 1)

for mod in asyncio concurrent curses dbm email html http idlelib \
    lib2to3 multiprocessing pydoc_data sqlite3 tkinter turtledemo \
    unittest venv wsgiref xmlrpc distutils ensurepip; do
    echo "Removing stdlib module: $mod"
    rm -rf "$PYTHON_LIB_DIR/$mod"
    test_dmgbuild
done

for ext in _asyncio _bz2 _codecs_{cn,hk,iso2022,jp,kr,tw} _crypt \
    _curses{,_panel} _{dbm,gdbm} _lzma _multiprocessing _posixshmem \
    _queue _sqlite3 _tkinter _uuid audioop nis ossaudiodev readline \
    spwd syslog termios xxlimited; do
    echo "Removing extension module: $ext"
    find "$PYTHON_LIB_DIR/lib-dynload" -name "${ext}*.so" -delete 2>/dev/null || true
    test_dmgbuild
done

echo "Removing pip and setuptools"
rm -rf "$PREFIX/bin/pip"* "$PREFIX/bin/easy_install"*
SITE_PACKAGES="$PYTHON_LIB_DIR/site-packages"
rm -rf "$SITE_PACKAGES"/{pip,setuptools}*
test_dmgbuild

echo "Removing test files, bytecode, and metadata"
find "$PREFIX" -type d \( -name test -o -name tests -o -name __pycache__ \) -exec rm -rf {} + 2>/dev/null || true
find "$PREFIX" -type f \( -name "*.pyc" -o -name "*.pyo" -o -name "test_*.py" \) -delete
find "$PREFIX" -type d \( -name "*.dist-info" -o -name "*.egg-info" \) -exec rm -rf {} + 2>/dev/null || true

# Remove dev files
rm -rf "$PREFIX"/{include,share} "$PREFIX/lib"/{pkgconfig,*.a} "$PREFIX/lib/python*/config-*"

# Clean up
find "$PREFIX" -type d -empty -delete 2>/dev/null || true

##############################################################################
# STRIP BINARIES
##############################################################################

strip -x "$PREFIX/bin/python3"
find "$PREFIX/lib" -name "*.so" -exec strip -x {} +

###############################################################################
# RPATH FIXES (SAFE)
###############################################################################

add_rpath_if_missing() {
    local bin="$1"
    local rpath="$2"
    if ! otool -l "$bin" | grep -q "path $rpath "; then
        install_name_tool -add_rpath "$rpath" "$bin"
    fi
}

# python executable
add_rpath_if_missing "$PREFIX/bin/python3" "@executable_path/../lib"

# extension modules
find "$PREFIX/lib" -name "*.so" | while read -r so; do
    add_rpath_if_missing "$so" "@loader_path"
done

###############################################################################
# BUNDLE OPENSSL DYLIBS — rewrite Homebrew paths to @loader_path-relative
###############################################################################
# _ssl.so and _hashlib.so link against Homebrew's libssl/libcrypto. We copy dylibs into lib-dynload/ alongside the .so files and rewrite every reference so the bundle is self-contained and passes the Homebrew-leak guardrail.

DYNLOAD_DIR="$(find "$PREFIX/lib" -maxdepth 2 -type d -name lib-dynload | head -n 1)"

bundle_openssl_dylib() {
    local src="$1"
    local name
    name="$(basename "$src")"
    local dst="$DYNLOAD_DIR/$name"
    if [[ ! -f "$dst" ]]; then
        cp "$src" "$dst"
        install_name_tool -id "@loader_path/$name" "$dst"
    fi
}

is_homebrew_path() {
    local p="$1"
    [[ "$p" == /opt/homebrew/* || "$p" == /usr/local/opt/* || "$p" == /usr/local/Cellar/* || "$p" == /usr/local/lib/lib* ]]
}

# Pass 1: copy every Homebrew dylib referenced by .so files into DYNLOAD_DIR
while IFS= read -r so; do
    while IFS= read -r ref; do
        if is_homebrew_path "$ref"; then
            bundle_openssl_dylib "$ref"
        fi
    done < <(otool -L "$so" 2>/dev/null | awk 'NR>1 {print $1}')
done < <(find "$DYNLOAD_DIR" -name "*.so")

# Pass 2: rewrite Homebrew references in both .so and the newly copied .dylib files
# (dylibs like libssl reference libcrypto via their original Homebrew path)
while IFS= read -r bin; do
    while IFS= read -r ref; do
        if is_homebrew_path "$ref"; then
            local_name="$(basename "$ref")"
            # If the dependency wasn't already bundled in pass 1, copy it now
            bundle_openssl_dylib "$ref"
            install_name_tool -change "$ref" "@loader_path/$local_name" "$bin"
        fi
    done < <(otool -L "$bin" 2>/dev/null | awk 'NR>1 {print $1}')
done < <(find "$DYNLOAD_DIR" \( -name "*.so" -o -name "*.dylib" \))

# ###############################################################################
# # ENTRYPOINT SCRIPT
# ###############################################################################

cat >"$DIR_TO_ARCHIVE/dmgbuild" <<'EOF'
#!/bin/bash
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
export PYTHONPATH="$ROOT/python/lib"
exec "$ROOT/python/bin/python3" -m dmgbuild "$@"
EOF

chmod +x "$DIR_TO_ARCHIVE/dmgbuild"

###############################################################################
# MOVE FINAL RUNTIME
###############################################################################

mv "$PREFIX" "$DIR_TO_ARCHIVE/python"

###############################################################################
# CODESIGN
###############################################################################

echo "🔐 Codesigning…"

find "$DIR_TO_ARCHIVE" -type f \
\( -name "*.so" -o -name "*.dylib" -o -perm +111 \) \
-exec codesign --remove-signature {} \; || true

find "$DIR_TO_ARCHIVE" -type f \
\( -name "*.so" -o -name "*.dylib" \) \
-exec codesign --force \
--sign "$CODESIGN_IDENTITY" \
{} \;

codesign --force \
--sign "$CODESIGN_IDENTITY" \
"$DIR_TO_ARCHIVE/python/bin/python3"
codesign --force \
--sign "$CODESIGN_IDENTITY" \
"$DIR_TO_ARCHIVE/dmgbuild"

###############################################################################
# GUARDRAILS — fail the build if Homebrew leaked or deployment target is wrong
###############################################################################
echo "🔎 Asserting no Homebrew leak and correct deployment target"

# 1) No Mach-O in the bundle may reference /usr/local/... or /opt/homebrew/...
LEAKS=""
while IFS= read -r f; do
    refs=$(otool -L "$f" 2>/dev/null \
        | awk 'NR>1 {print $1}' \
        | grep -E '^(/usr/local/|/opt/homebrew/)' || true)
    if [ -n "$refs" ]; then
        LEAKS+=$'\n'"$f:"$'\n'"$refs"
    fi
done < <(find "$DIR_TO_ARCHIVE" -type f \( -name "*.so" -o -name "*.dylib" -o -perm +111 \))

if [ -n "$LEAKS" ]; then
    echo "❌ Homebrew dylib reference leaked into binary:${LEAKS}"
    exit 1
fi

# 2) python3 must advertise minos == MACOSX_DEPLOYMENT_TARGET
VTOUT="$(vtool -show-build "$DIR_TO_ARCHIVE/python/bin/python3" 2>/dev/null || true)"
if ! echo "$VTOUT" | grep -Eq "minos[[:space:]]+${MACOSX_DEPLOYMENT_TARGET}([. ]|$)"; then
    echo "❌ python3 deployment target != ${MACOSX_DEPLOYMENT_TARGET}:"
    echo "$VTOUT"
    exit 1
fi
echo "✅ Guardrails passed (no Homebrew refs, minos=${MACOSX_DEPLOYMENT_TARGET})"

###############################################################################
# ARCHIVE (do it now to avoid including later test and cache files)
###############################################################################

echo "📄 Downloading component licenses..."
mkdir -p "${DIR_TO_ARCHIVE}/LICENSES"
curl -fsSL "https://raw.githubusercontent.com/dmgbuild/dmgbuild/master/LICENSE" \
  -o "${DIR_TO_ARCHIVE}/LICENSES/LICENSE.dmgbuild"
if [ ! -f "${DIR_TO_ARCHIVE}/python/LICENSE.txt" ]; then
  curl -fsSL "https://raw.githubusercontent.com/python/cpython/v${PYTHON_VERSION}/LICENSE" \
    -o "${DIR_TO_ARCHIVE}/LICENSES/LICENSE.python"
fi
echo "  ✓ Licenses downloaded"

echo "📦 Creating archive…"
cd "${DIR_TO_ARCHIVE}"

ARCHIVE="dmgbuild-bundle-${ARCH}-${DMGBUILD_VERSION}.tar.gz"
ARCHIVE_PATH="${OUTPUT_DIR}/${ARCHIVE}"

tar -czf "${ARCHIVE_PATH}" -C "${DIR_TO_ARCHIVE}" .

shasum -a 256 "${ARCHIVE_PATH}" > "${ARCHIVE_PATH}.sha256"
echo "✅ Created ${ARCHIVE}"

###############################################################################
# VERIFY
###############################################################################

echo "🔍 Verifying…"

otool -L "$DIR_TO_ARCHIVE/python/bin/python3"

codesign --verify --strict --verbose=1 "$DIR_TO_ARCHIVE/python/bin/python3"
codesign --verify --strict --verbose=1 "$DIR_TO_ARCHIVE/dmgbuild"

find "$DIR_TO_ARCHIVE" -type f \
    \( -perm +111 -o -name "*.so" -o -name "*.dylib" \) \
    -exec codesign --verify --strict --verbose=1 {} \;

###############################################################################
# TESTING
###############################################################################
echo "🧪 Running tests…"

# Test 1: Python version
run_arch "$DIR_TO_ARCHIVE/python/bin/python3" --version

# Test 2: Core imports
run_arch "$DIR_TO_ARCHIVE/python/bin/python3" -c "
import sys, os, pathlib, re, struct
import plistlib, xml.etree.ElementTree
import binascii, base64, pickle
print('✓ Core modules work')
"

# Test 3: dmgbuild dependencies
run_arch "$DIR_TO_ARCHIVE/python/bin/python3" -c "
import dmgbuild
import ds_store
import mac_alias
print('✓ dmgbuild dependencies work')
"

# Test 4: dmgbuild CLI
run_arch "$DIR_TO_ARCHIVE/python/bin/python3" -m dmgbuild --help >/dev/null
echo "✓ dmgbuild CLI works"

# Test 5: Create test DMG with entrypoint
cat > "$TEST_DIR/test_settings.py" << 'EOF'
format = 'UDBZ'
size = None
files = []
symlinks = {}
EOF

"$DIR_TO_ARCHIVE/dmgbuild" --help
"$DIR_TO_ARCHIVE/dmgbuild" -s "$TEST_DIR/test_settings.py" --detach-retries 1 Test "$TEST_DIR/test.dmg"
echo "✓ Can create DMG"

echo "✅ All tests passed!"

###############################################################################
# DONE
###############################################################################

SIZE="$(du -sh "$DIR_TO_ARCHIVE" | cut -f1)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ DONE"
echo "• Arch: $ARCH"
echo "• Size: $SIZE"
echo "• Path: $DIR_TO_ARCHIVE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Path: ${ARCHIVE_PATH}"
echo "Size: $(du -sh "${ARCHIVE_PATH}" | cut -f1)"

echo "✅ Created ${ARCHIVE}"
