#!/bin/bash

set -euo pipefail

CWD=$(cd "$(dirname "$BASH_SOURCE")" && pwd)
source "$CWD/constants.sh"
LIB_DIR="$RUBY_PREFIX/lib"

# ===== Prepare folders =====
echo "🪏 Creating install directories..."
rm -rf "$INSTALL_DIR" "$SOURCE_DIR"
mkdir -p "$INSTALL_DIR" "$SOURCE_DIR"

# ===== Download Ruby source =====
echo "⬇️ Downloading Ruby $RUBY_VERSION source..."
cd "$SOURCE_DIR"
curl -O "https://cache.ruby-lang.org/pub/ruby/${RUBY_VERSION%.*}/ruby-${RUBY_VERSION}.tar.gz"
tar -xzf "ruby-${RUBY_VERSION}.tar.gz"
cd "ruby-${RUBY_VERSION}"

# ===== Configure and compile Ruby =====
BASE_FLAGS=(
    "--prefix=$RUBY_PREFIX"
    --disable-install-doc
    --enable-shared
    --enable-load-relative
)
echo "🔨 Configuring and compiling Ruby..."
if [ "$(uname)" = "Darwin" ]; then
    echo "  ⚒️ Installing dependencies..."
    xcode-select --install 2>/dev/null || true
    brew install -q autoconf automake pkg-config openssl@3 ncurses readline zlib p7zip libyaml xz gmp coreutils bison

    echo "  🍎 Compiling for MacOS."
    autoconf
    ./autogen.sh

    BREW_PREFIX="$(brew --prefix)"
    export CFLAGS="-I$BREW_PREFIX/include"
    export CPPFLAGS="$CFLAGS"
    export LDFLAGS="-L$BREW_PREFIX/lib  -Wl,-headerpad_max_install_names"
    export PKG_CONFIG_PATH="$BREW_PREFIX/opt/openssl@3/lib/pkgconfig"
    export PATH="$BREW_PREFIX/bin:$PATH"

    echo "  ⚙️ Running configure..."
    ./configure "${BASE_FLAGS[@]}" \
        --with-opt-dir="$BREW_PREFIX" \
        --with-openssl-dir="$(brew --prefix openssl@3)" \
        --with-readline-dir="$(brew --prefix readline)" \
        --with-zlib-dir="$(brew --prefix zlib)" \
        --with-libyaml-dir=$(brew --prefix libyaml) \
        1>/dev/null

    echo "  🔨 Building Ruby..."
    make -j"$(sysctl -n hw.ncpu)" 1>/dev/null
    echo "  ⤵️ Installing Ruby..."
    make install 1>/dev/null
else
    echo "  🐧 Compiling for Linux."
    autoconf
    ./autogen.sh

    COMMON_FLAGS=(
        "${BASE_FLAGS[@]}"
        "--with-opt-dir=/usr"
        "--with-libyaml-dir=/usr"
        "--with-openssl-dir=/usr"
        "--with-zlib-dir=/usr"
        "--with-readline-dir=/usr"
        "--with-baseruby=$(which ruby)"
    )
    echo "  ⚙️ Running configure..."
    if [ "$TARGET_ARCH" = "i386" ]; then
        echo " ✏️ Using 32-bit architecture flags."
        ./configure "${COMMON_FLAGS[@]}" \
            --host=i386-linux-gnu \
            CC="gcc -m32" \
            CXX="g++ -m32" \
            1>/dev/null
    else
        ./configure "${COMMON_FLAGS[@]}" 1>/dev/null
    fi

    echo "  🔨 Building Ruby..."
    make -j$(nproc) 1>/dev/null
    echo "  ⤵️ Installing Ruby..."
    make install 1>/dev/null
fi

echo "💎 Ruby $RUBY_VERSION installed to $RUBY_PREFIX"
echo "🗑️ Cleaning up source code download..."
rm -rf "$SOURCE_DIR"
echo "✅ Done!"
