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
    --disable-rpath
    --disable-dtrace
    --disable-jit-support

    --disable-shared
    --with-static-linked-ext
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
        --with-libyaml-dir=$(brew --prefix libyaml) \
        --with-openssl-dir="$(brew --prefix openssl@3)" \
        --with-zlib-dir="$(brew --prefix zlib)" \
        --with-readline-dir="$(brew --prefix readline)" \
        --with-baseruby="$(which ruby)" \
        --with-out-ext=debug,rbs,syslog,nkf,bigdecimal,racc \
        1>/dev/null

    echo "  ⚒️ Clearing default/bundled gems (includes native extensions that can't be portable)..."
    rm -rf .bundle gems
    mkdir -p gems && touch gems/bundled_gems

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
        "--with-out-ext=debug,rbs,syslog,nkf,bigdecimal,racc"
    )

    export CFLAGS="-fPIC -O2"
    export LDFLAGS="-fPIC -static-libgcc -static-libstdc++"
    export CPPFLAGS="$CFLAGS"

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
