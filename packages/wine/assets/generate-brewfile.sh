#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_LOG="${CONFIG_LOG:-$SCRIPT_DIR/../build/wine64-build/config.log}"
BREWFILE="$SCRIPT_DIR/Brewfile"
GENERATED="$SCRIPT_DIR/Brewfile.generated"

if [[ ! -f "$CONFIG_LOG" ]]; then
    echo "❌ config.log not found: $CONFIG_LOG"
    exit 1
fi

echo "🍺 Generating Brewfile from config.log"

# Map linker libs → Homebrew formulae
map_lib_to_brew() {
    case "$1" in
        xml2) echo "libxml2" ;;
        png) echo "libpng" ;;
        jpeg) echo "jpeg-turbo" ;;
        gnutls) echo "gnutls" ;;
        gmp) echo "gmp" ;;
        z) echo "zlib" ;;
        bz2) echo "bzip2" ;;
        lzma) echo "xz" ;;
        *) return 1 ;;
    esac
}

{
    echo "# AUTO-GENERATED – DO NOT EDIT"
    echo "# Generated from Wine config.log"
    echo
    echo "# Toolchain"
    echo 'brew "bison"'
    echo 'brew "flex"'
    echo 'brew "gettext"'
    echo 'brew "libtool"'
    echo 'brew "mingw-w64"'
    echo 'brew "pkg-config"'
    echo

    echo "# Wine dependencies"

    grep -oE -e '-l[a-zA-Z0-9_]+' "$CONFIG_LOG" \
    | sed 's/^-l//' \
    | sort -u \
    | while read -r lib; do
        if brew_pkg=$(map_lib_to_brew "$lib"); then
            echo "brew \"$brew_pkg\""
        fi
    done | sort

    echo
    echo "# Build helpers"
    echo 'brew "autoconf"'
    echo 'brew "automake"'
    echo 'brew "make"'
    echo 'brew "xz"'
} > "$GENERATED"

echo "✅ Generated $GENERATED"

# Compare with committed Brewfile. If CI, fail if out of date.
if [[ "${CI:-}" == "true" ]]; then
    if ! diff -u "$BREWFILE" "$GENERATED"; then
        echo "❌ Brewfile out of date. Run build locally and commit changes."
        exit 1
    fi
fi

if diff -u "$BREWFILE" "$GENERATED" >/dev/null; then
    echo "🍻 Brewfile unchanged"
    exit 0
fi

echo "⚠️ Brewfile changed – updating"
cp "$GENERATED" "$BREWFILE"
rm "$GENERATED"

echo
echo "📝 Brewfile updated."
echo "👉 Please review and commit:"
echo "   git add Brewfile"
echo "   git commit -m 'chore: update Brewfile from Wine build'"
