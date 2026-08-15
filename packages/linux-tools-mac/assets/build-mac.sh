#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "❌ Must be run on macOS"
    exit 1
fi

XCODE_VER="$(xcodebuild -version 2>/dev/null | awk '/^Xcode /{print $2}')"
XCODE_MAJOR="${XCODE_VER%%.*}"
if [[ -z "$XCODE_MAJOR" || "$XCODE_MAJOR" -lt 26 ]]; then
    echo "❌ Xcode 26+ required (found: ${XCODE_VER:-none})"
    echo "   install_name_tool in Xcode < 26 rejects Homebrew ld_prime binaries."
    echo "   On macos-15 runners select a preinstalled Xcode 26, e.g.:"
    echo "   sudo xcode-select -s /Applications/Xcode_26.3.app/Contents/Developer"
    echo "   (Avoid macos-26 runners: their Homebrew bottles require macOS >= 26 at runtime.)"
    exit 1
fi

### ================================
### ARGS
### ================================
ARCH=""
OUTPUT_DIR=""
ROOT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)       ARCH="$2";       shift 2 ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        --root)       ROOT="$2";       shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
OUTPUT_DIR="${OUTPUT_DIR:-${ROOT}/out/linux-tools-mac}"
ARCH="${ARCH:-$(uname -m)}"

if [[ "$ARCH" != "arm64" && "$ARCH" != "x86_64" ]]; then
    echo "❌ Unsupported ARCH: $ARCH"
    exit 1
fi

### ================================
### CONFIG
### ================================
TMP_DIR="/tmp/linux-tools-mac-build-${ARCH}"
BUNDLE_DIR="${TMP_DIR}/linux-tools-mac"
BIN_DIR="${BUNDLE_DIR}/bin"
LIB_DIR="${BUNDLE_DIR}/lib"

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT INT TERM

# Binaries to collect per formula — "formula:bin1 bin2 bin3" entries
FORMULA_BINS=(
    "gnu-tar:gtar"
    "lzip:lzip"
    "makedepend:makedepend"
    "glib:gapplication gdbus gdbus-codegen gio gio-querymodules glib-compile-resources glib-compile-schemas glib-genmarshal glib-gettextize glib-mkenums gobject-query gresource gsettings gtester gtester-report"
    "libgsf:gsf gsf-office-thumbnailer gsf-vba-dump"
    "libtool:glibtool glibtoolize"
    "pcre:pcre-config pcregrep pcretest"
    "gettext:autopoint envsubst gettext gettext.sh gettextize msgattrib msgcat msgcmp msgcomm msgconv msgen msgexec msgfilter msgfmt msggrep msginit msgmerge msgunfmt msguniq ngettext recode-sr-latin xgettext"
    "binutils:gar ar"
)

echo "🛠️  linux-tools-mac macOS bundle"
echo "   Arch:   $ARCH"
echo "   Xcode:  $XCODE_VER"
echo "   Output: $OUTPUT_DIR"

### ================================
### CLEAN
### ================================
rm -rf "$TMP_DIR"
mkdir -p "$BIN_DIR" "$LIB_DIR"

### ================================
### INSTALL DEPENDENCIES
### ================================
echo ""
echo "📦 Installing brew formulas..."
brew install gnu-tar lzip makedepend glib libgsf libtool pcre gettext binutils

### ================================
### COPY BINARIES
### ================================
echo ""
echo "📋 Copying binaries..."

for entry in "${FORMULA_BINS[@]}"; do
    formula="${entry%%:*}"
    bins="${entry#*:}"
    prefix="$(brew --prefix "$formula" 2>/dev/null || true)"
    if [[ -z "$prefix" ]]; then
        echo "  ⚠️  Could not find prefix for $formula, skipping"
        continue
    fi
    for bin in $bins; do
        src="$prefix/bin/$bin"
        if [[ -f "$src" || -L "$src" ]]; then
            echo "  ➕ $formula/$bin"
            cp -L "$src" "$BIN_DIR/$bin"
            chmod u+w,a+x "$BIN_DIR/$bin"
        else
            echo "  ⏭️  $formula/$bin not found, skipping"
        fi
    done
done

### ================================
### COPY LICENSE FILES
### ================================
echo ""
echo "📄 Copying license files..."
mkdir -p "$BUNDLE_DIR/LICENSES"

for entry in "${FORMULA_BINS[@]}"; do
    formula="${entry%%:*}"
    license_prefix="$(brew --prefix "$formula" 2>/dev/null || true)"
    if [[ -z "$license_prefix" ]]; then
        echo "  ⚠️  Could not find prefix for $formula, skipping licenses"
        continue
    fi

    license_dir="$BUNDLE_DIR/LICENSES/$formula"
    mkdir -p "$license_dir"

    found=0
    for name in COPYING LICENSE LICENCE COPYING.LIB AUTHORS; do
        src="$license_prefix/$name"
        if [[ -f "$src" ]]; then
            cp "$src" "$license_dir/$name"
            echo "  📄 $formula/$name"
            found=1
        fi
    done
    if [[ "$found" -eq 0 ]]; then
        echo "  ⚠️  No license file found for $formula in $license_prefix"
    fi
done

### ================================
### COLLECT DYLIB DEPENDENCIES
### ================================
echo ""
echo "📚 Collecting dylib dependencies..."

should_skip_lib() {
    local dep="$1"
    [[ "$dep" == /usr/lib/* ]] && return 0
    [[ "$dep" == /System/* ]] && return 0
    [[ "$dep" == @* ]] && return 0
    return 1
}

is_macho() {
    file -b "$1" 2>/dev/null | grep -q '^Mach-O'
}

collect_deps() {
    local binary="$1"
    is_macho "$binary" || return 0
    otool -L "$binary" 2>/dev/null | awk 'NR>1 {print $1}' | while read -r dep; do
        should_skip_lib "$dep" && continue
        [[ ! -f "$dep" ]] && continue

        local dep_name
        dep_name="$(basename "$dep")"
        local dest="$LIB_DIR/$dep_name"

        if [[ ! -f "$dest" ]]; then
            echo "    📥 $dep_name"
            cp -L "$dep" "$dest"
            chmod u+w "$dest"
            # Recurse into this library's own deps
            collect_deps "$dest"
        fi
    done
}

find "$BIN_DIR" -type f | while read -r bin; do
    collect_deps "$bin"
done

# Also collect deps of libs (they may have deps we missed)
find "$LIB_DIR" -name "*.dylib" -type f | while read -r lib; do
    collect_deps "$lib"
done

### ================================
### PATCH DYLIB REFERENCES
### ================================
echo ""
echo "🔧 Patching dylib references..."

patch_binary() {
    local binary="$1"
    local is_lib="${2:-false}"

    is_macho "$binary" || return 0

    # Set install name for dylibs
    if [[ "$is_lib" == "true" ]]; then
        local lib_name
        lib_name="$(basename "$binary")"
        install_name_tool -id "@loader_path/$lib_name" "$binary" 2>/dev/null || true
    fi

    # Patch all absolute non-system dep references
    otool -L "$binary" 2>/dev/null | awk 'NR>1 {print $1}' | while read -r dep; do
        should_skip_lib "$dep" && continue

        local dep_name
        dep_name="$(basename "$dep")"
        local dest="$LIB_DIR/$dep_name"

        if [[ -f "$dest" ]]; then
            local new_path
            if [[ "$is_lib" == "true" ]]; then
                new_path="@loader_path/$dep_name"
            else
                new_path="@loader_path/../lib/$dep_name"
            fi
            local it_err
            it_err="$(install_name_tool -change "$dep" "$new_path" "$binary" 2>&1)" \
                || echo "    ⚠️  patch failed [$(basename "$binary")] $dep: $it_err"
        fi
    done
}

find "$BIN_DIR" -type f | while read -r bin; do
    echo "  🔁 bin/$(basename "$bin")"
    patch_binary "$bin" "false"
done

find "$LIB_DIR" -name "*.dylib" -type f | while read -r lib; do
    echo "  🔁 lib/$(basename "$lib")"
    patch_binary "$lib" "true"
done

### ================================
### STRIP SYMBOLS
### ================================
echo ""
echo "✂️  Stripping symbols..."
find "$BUNDLE_DIR" -type f | while read -r f; do
    strip -x "$f" 2>/dev/null || true
done

### ================================
### AD-HOC CODESIGN
### ================================
echo ""
echo "🔏 Code signing..."

# Sign libs first (executables may load them)
find "$LIB_DIR" -name "*.dylib" -type f | while read -r lib; do
    codesign --force --sign - "$lib" 2>/dev/null || true
done

find "$BIN_DIR" -type f | while read -r bin; do
    codesign --force --sign - "$bin" 2>/dev/null || true
done

### ================================
### VERSION.txt
### ================================
echo ""
echo "📝 Writing VERSION.txt..."
{
    echo "platform: darwin"
    echo "arch: $ARCH"
    echo "created_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo ""
    for formula in gnu-tar lzip makedepend glib libgsf libtool pcre gettext binutils; do
        ver="$(brew info --json "$formula" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['versions']['stable'])" 2>/dev/null || echo "unknown")"
        echo "$formula: $ver"
    done
} > "$BUNDLE_DIR/VERSION.txt"

### ================================
### ARCHIVE
### ================================
echo ""
echo "📦 Creating archive..."
mkdir -p "$OUTPUT_DIR"

ARCHIVE_ARCH="$ARCH"
ARCHIVE_NAME="linux-tools-mac-darwin-${ARCHIVE_ARCH}.tar.gz"
ARCHIVE_PATH="$OUTPUT_DIR/$ARCHIVE_NAME"

tar -czf "$ARCHIVE_PATH" -C "$TMP_DIR" linux-tools-mac
shasum -a 256 "$ARCHIVE_PATH" > "${ARCHIVE_PATH}.sha256"

rm -rf "$TMP_DIR"

### ================================
### TEST
### ================================
echo ""
echo "🧪 Running tests..."

VERIFY_DIR="/tmp/linux-tools-mac-verify-$$"
mkdir -p "$VERIFY_DIR"
tar -xzf "$ARCHIVE_PATH" -C "$VERIFY_DIR"

bash "$ROOT/assets/test.sh" --bundle-dir "$VERIFY_DIR/linux-tools-mac"

rm -rf "$VERIFY_DIR"

### ================================
### DONE
### ================================
SIZE="$(du -sh "$ARCHIVE_PATH" | cut -f1)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ DONE"
echo "• Arch:    $ARCH"
echo "• Archive: $ARCHIVE_NAME"
echo "• Size:    $SIZE"
echo "• Path:    $ARCHIVE_PATH"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
