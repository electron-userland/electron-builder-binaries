#!/bin/bash

set -euo pipefail

CWD=$(cd "$(dirname "$BASH_SOURCE")" && pwd)
source "$CWD/constants.sh"

GEM_LIST=("fpm -v 1.16.0" "ruby-xz") # Add other gems (with or without version arg) here
ENTRYPOINT_GEMS=("fpm")

# ===== Prepare folders =====
OUTPUT_DIR="$BASEDIR/out/fpm"
mkdir -p "$OUTPUT_DIR"

# ===== Create wrapper scripts =====
echo "🔨 Creating environment script..."
echo "  ✏️ ruby.env -> $INSTALL_DIR/ruby.env"
cat <<EOF >"$INSTALL_DIR/ruby.env"
#!/bin/bash
# Portable Ruby environment setup
RUBY_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")/$RUBY_DIR_NAME" && pwd)"
RUBY_BIN="\$RUBY_DIR/bin"
export PATH="\$RUBY_BIN:\$PATH"
export GEM_HOME="\$RUBY_DIR/gems"
export GEM_PATH="\$GEM_HOME"
export RUBYLIB="\$RUBY_DIR/lib:\$RUBYLIB"
if [ "\$(uname)" = "Darwin" ]; then
    # Remove quarantine attribute on macOS
    # This is necessary to avoid the "ruby is damaged and can't be opened" error when running the ruby interpreter for the first time
    if grep -q "com.apple.quarantine" <<< "\$(xattr "\$RUBY_BIN/ruby")"; then
        xattr -d com.apple.quarantine "\$RUBY_BIN/ruby"
    fi
    export DYLD_LIBRARY_PATH="\$RUBY_DIR/lib\${DYLD_LIBRARY_PATH:+:\$DYLD_LIBRARY_PATH}"
else
    export LD_LIBRARY_PATH="\$RUBY_DIR/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
fi
EOF
chmod +x "$INSTALL_DIR/ruby.env"

# ===== Install gems =====
echo "💎 Installing gems..."
export PATH="$RUBY_PREFIX/bin:$PATH"
GEM_DIR="$RUBY_PREFIX/gems"
mkdir -p "$GEM_DIR"
export GEM_HOME="$GEM_DIR"
export GEM_PATH="$GEM_HOME"
for gem in "${GEM_LIST[@]}"; do
    gem_name=$(echo "$gem" | cut -d' ' -f1)
    echo "  ⤵️ Installing $gem_name"
    gem install --no-document $gem --quiet --env-shebang
done

echo "🔨 Creating entrypoint scripts for installed gems..."
for gem in "${ENTRYPOINT_GEMS[@]}"; do
    gem_name=$(echo "$gem" | cut -d' ' -f1)
    echo "  ✏️ $gem -> $INSTALL_DIR/$gem_name"
    cat <<EOF >"$INSTALL_DIR/$gem_name"
#!/bin/bash -e
# Portable Ruby environment setup
source "\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)/ruby.env"

exec "\$GEM_HOME/bin/$gem_name" "\$@"
EOF
    chmod +x "$INSTALL_DIR/$gem_name"
done

# ===== Patch Ruby and copy dependencies =====
LIB_DIR="$RUBY_PREFIX/lib"
if [ "$(uname)" = "Darwin" ]; then
    echo "  🗑️ Removing dSYM files"
    find $RUBY_PREFIX -type d -name "*.dSYM" -exec rm -rf {} +

    echo "  🍎 Patching portable Ruby bundle for MacOS."

    SHARED_LIB_DIR="$LIB_DIR"
    echo "  ⏩️ Copying shared libraries to $SHARED_LIB_DIR"
    mkdir -p "$SHARED_LIB_DIR"
    SHARED_LIBRARIES=(
        "$(brew --prefix openssl@3)/lib/*.dylib"
        "$(brew --prefix readline)/lib/*.dylib"
        "$(brew --prefix zlib)/lib/*.dylib"
        "$(brew --prefix libyaml)/lib/*.dylib"
        "$(brew --prefix xz)/lib/*.dylib"
        "$(brew --prefix gmp)/lib/*.dylib"
        "$(brew --prefix ncurses)/lib/*.dylib"
    )
    for pattern in "${SHARED_LIBRARIES[@]}"; do
        for filepath in $pattern; do
            dest="$SHARED_LIB_DIR/$(basename $filepath)"
            if [[ ! -f "$dest" ]]; then
                echo "    📝 Copying $filepath"
                cp -a "$filepath" "$dest"
            fi
        done
    done

    echo "📦 Making dylib references portable in: $RUBY_PREFIX"
    DEFAULT_RPATH="@executable_path/../lib"
    # === Known system libs (do not copy or patch) ===
    skip_libs=(
        "libSystem.B.dylib"
        "libc++.1.dylib"
    )
    should_skip() {
        local libname="$1"
        for skip in "${skip_libs[@]}"; do
            [[ "$libname" == "$skip" ]] && return 0
        done
        return 1
    }

    # === Ensure LC_RPATH exists
    ensure_rpath() {
        local bin="$1"
        if ! otool -l "$bin" | grep -q LC_RPATH; then
            echo "  ➕ Adding RPATH: $DEFAULT_RPATH"
            install_name_tool -add_rpath "$DEFAULT_RPATH" "$bin" || echo "  ⚠️ Failed to add RPATH"
        fi
    }

    # === Compute relative @loader_path path to .dylib
    compute_loader_path() {
        set -e
        local file="$1"
        local lib="$2"
        local file_dir
        file_dir=$(dirname "$file")
        local rel_path
        rel_path=$(grealpath --relative-to="$file_dir" "$lib")
        echo "@loader_path/$rel_path"
    }

    # === Normalize @rpath/../lib → @rpath
    normalize_rpath() {
        local file="$1"
        otool -L "$file" | awk 'NR>1 {print $1}' | grep '@rpath/../lib/' || return 0
        while IFS= read -r dep; do
            clean_dep="@rpath/$(basename "$dep")"
            echo "  🔁 Normalize: $dep → $clean_dep"
            install_name_tool -change "$dep" "$clean_dep" "$file" || echo "  ⚠️ Failed to normalize $dep"
        done < <(otool -L "$file" | awk 'NR>1 {print $1}' | grep '@rpath/../lib/')
    }

    # === Process all binaries, dylibs, and bundles
    find "$RUBY_PREFIX" \( -name '*.dylib' -o -name '*.bundle' -o -type f -perm +111 \) | while read -r file; do
        echo "🔍 Inspecting: $file"

        # Rewrite absolute dylib references
        abs_deps=$(otool -L "$file" | awk 'NR>1 {print $1}' | grep -E '^/' || true)
        if [[ -z "$abs_deps" ]]; then
            echo "  ✅ No absolute dylib references."
        else
            while IFS= read -r dep; do
                dep_basename=$(basename "$dep")
                if should_skip "$dep_basename"; then
                    echo "  🔕 Skipping system lib: $dep_basename"
                    continue
                fi

                lib_target="$LIB_DIR/$dep_basename"

                # Autocopy if missing
                if [[ ! -f "$lib_target" && -f "$dep" ]]; then
                    echo "  📥 Copying $dep → $lib_target"
                    cp "$dep" "$lib_target"
                fi

                if [[ -f "$lib_target" ]]; then
                    loader_path_ref=$(compute_loader_path "$file" "$lib_target")
                    echo "  🔁 Absolute: $dep → $loader_path_ref"
                    install_name_tool -change "$dep" "$loader_path_ref" "$file" || echo "  ⚠️ Failed to patch $dep"
                else
                    echo "  ⚠️ Missing: $dep_basename could not be found or copied"
                fi
            done <<<"$abs_deps"
        fi

        # Rewrite @executable_path to @rpath
        exec_deps=$(otool -L "$file" | awk 'NR>1 {print $1}' | grep '@executable_path' || true)
        if [[ -z "$exec_deps" ]]; then
            echo "  ✅ No @executable_path references."
        else
            while IFS= read -r dep; do
                new_path="@rpath/${dep#@executable_path/}"
                echo "  🔁 ExecPath: $dep → $new_path"
                install_name_tool -change "$dep" "$new_path" "$file" || echo "  ⚠️ Failed to rewrite exec path: $dep"
                ensure_rpath "$file"
            done <<<"$exec_deps"
        fi

        normalize_rpath "$file"
    done

    echo "✅ All dylib references made portable. Autocopied missing libraries where needed."
else
    echo "  🐧 Patching portable Ruby bundle for Linux."

    echo "  ⏩️ Copying shared libraries to $LIB_DIR"
    SHARED_LIBRARIES=(
        "libssl.so*"
        "libcrypto.so*"
        "libreadline.so*"
        "libz.so*"
        "libyaml-cpp.so*"
        "liblzma.so*"
    )
    for pattern in "${SHARED_LIBRARIES[@]}"; do
        find /usr/lib /lib -type f -name "$pattern" 2>/dev/null | while read -r filepath; do
            dest="$LIB_DIR/$(basename $filepath)"
            if [[ ! -f "$dest" ]]; then
                echo "    📝 Copying $filepath"
                cp -a "$filepath" "$dest"
            fi
        done
    done

    echo "  🔍 Scanning Ruby extensions for additional shared libraries..."
    IFS=$'\n'
    LDD_SEARCH_PATHS=("$RUBY_PREFIX/bin/ruby" $(find "$LIB_DIR/ruby" -type f -name '*.so'))
    unset IFS

    for ext_so in "${LDD_SEARCH_PATHS[@]}"; do
        if [[ ! -f "$ext_so" ]]; then
            echo "  ⏩️ Skipping $ext_so (not a file)"
            continue
        fi
        SO_DIR=$(dirname "$ext_so")
        REL_RPATH=$(realpath --relative-to="$SO_DIR" "$LIB_DIR")
        echo "    🩹 Patching $(realpath --relative-to="$RUBY_PREFIX" "$ext_so") to rpath: \$ORIGIN/$REL_RPATH"
        patchelf --set-rpath "\$ORIGIN/$REL_RPATH" "$ext_so"

        ldd "$ext_so" | awk '/=>/ { print $3 }' | while read -r dep; do
            if [[ -f "$dep" ]]; then
                dest="$LIB_DIR/$(basename $dep)"
                if [[ ! -f "$dest" ]]; then
                    echo "    📝 Copying $dep"
                    cp -u "$dep" "$LIB_DIR/"
                fi
            fi
        done
    done
    echo "✅ All shared library paths rewritten using @rpath where applicable."
fi

echo "✂️ Stripping symbols and measuring size savings..."
total_saved=0
# Platform detection
if [[ "$(uname -s)" == "Darwin" ]]; then
    STAT_CMD='stat -f%z'
    STRIP_CMD='strip -x'
else
    STAT_CMD='stat -c%s'
    STRIP_CMD='strip --strip-unneeded'
fi
# Strip and log
find "$RUBY_PREFIX" \( -name '*.dylib' -o -name '*.so' -o -name '*.so.*' -o -name '*.bundle' -o -type f -perm -111 \) | while read -r bin; do
    if [[ ! -f "$bin" || -L "$bin" ]]; then
        # echo "  ⏭️  Skipping (symlink or invalid): $bin"
        continue
    fi
    orig_size=$($STAT_CMD "$bin" 2>/dev/null || echo 0)

    if $STRIP_CMD "$bin" 2>/dev/null; then
        new_size=$($STAT_CMD "$bin" 2>/dev/null || echo 0)
        if [[ "$new_size" -gt 0 && "$orig_size" -gt "$new_size" ]]; then
            saved=$((orig_size - new_size))
            total_saved=$((total_saved + saved))
        else
            saved=0
        fi
        printf "  ➖ Stripped: %-60s saved: %6d bytes\n" "$(basename "$bin")" "$saved"
    else
        echo "  ⚠️ Could not strip: $bin"
    fi
done
echo "💾 Total space saved: $total_saved bytes (~$((total_saved / 1024)) KB)"

# ===== Create VERSION file =====
echo "🔨 Creating VERSION file..."
RUBY_VERSION_VERBOSE="$($RUBY_PREFIX/bin/ruby --version)"
FPM_VERSION="$($INSTALL_DIR/fpm --version | cut -d' ' -f2)"
echo "$RUBY_VERSION_VERBOSE" >$INSTALL_DIR/VERSION.txt
echo "fpm: $FPM_VERSION" >>$INSTALL_DIR/VERSION.txt

echo "🔨 Creating portable archive..."
cd "$INSTALL_DIR"
ARCHIVE_NAME="fpm-${FPM_VERSION}-ruby-${RUBY_VERSION}-$(uname -s | tr '[:upper:]' '[:lower:]')-${TARGET_ARCH:-$(uname -m)}.7z"

7za a -mx=9 -mfb=64 "$OUTPUT_DIR/$ARCHIVE_NAME" "$INSTALL_DIR"/*
echo "🚢 Portable Ruby $RUBY_VERSION built and bundled at:"
echo "  ⏭️ Directory: $OUTPUT_DIR"
echo "  ⏭️ Full Path: $OUTPUT_DIR/$ARCHIVE_NAME"
