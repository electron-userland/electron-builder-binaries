#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "❌ Must be run on macOS"
    exit 1
fi

### ================================
### CONFIG
### ================================
ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
OUTPUT_DIR="${2:-${ROOT}/dist}"
PYTHON_VERSION="${3:-3.11.8}"
DMGBUILD_VERSION="${4:-1.6.6}"
CODESIGN_IDENTITY="${5:-"-"}" # "-" = ad-hoc
ARCH="${6:-$(uname -m)}"

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

MACOS_DEPLOYMENT_TARGET="11.0"
BUILD_DIR="${ROOT}/build"
SRC_DIR="$BUILD_DIR/src"
TEST_DIR="$BUILD_DIR/test"
PREFIX="$BUILD_DIR/python"
DIR_TO_ARCHIVE="${BUILD_DIR}/dmg-builder-${ARCH}-${DMGBUILD_VERSION}"

echo "🐍 dmgbuild portable bundler"
echo "📁 Output directory: ${DIR_TO_ARCHIVE}"
echo "🔢 Python version: ${PYTHON_VERSION}"
echo "📦 dmgbuild version: ${DMGBUILD_VERSION}"
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
export MACOSX_DEPLOYMENT_TARGET
export CC=clang
export CXX=clang++
export CFLAGS="-O3 -fPIC -arch ${ARCH}"
export LDFLAGS="-arch ${ARCH}"

unset CPATH LIBRARY_PATH PKG_CONFIG_PATH SDKROOT

### ================================
### CONFIGURE
### ================================
run_arch ./configure \
--prefix="$PREFIX" \
--enable-optimizations \
--disable-shared \
--disable-test-modules \
ac_cv_func_clock_gettime=no

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

run_arch "$PREFIX/bin/python3" -m pip install --upgrade pip --no-warn-script-location
run_arch "$PREFIX/bin/python3" -m pip install --no-warn-script-location --no-cache dmgbuild==${DMGBUILD_VERSION}

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

codesign --force  \
--sign "$CODESIGN_IDENTITY" \
"$DIR_TO_ARCHIVE/python/bin/python3"
codesign --force  \
--sign "$CODESIGN_IDENTITY" \
"$DIR_TO_ARCHIVE/dmgbuild"

###############################################################################
# ARCHIVE (do it now to avoid including later test and cache files)
###############################################################################

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
