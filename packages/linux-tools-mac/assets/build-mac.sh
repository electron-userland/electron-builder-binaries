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
DEP_FORMULAS_FILE="${TMP_DIR}/dep-formulas.txt"

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT INT TERM

# Only the tools electron-builder needs when building Linux targets on macOS:
#   - gtar: fpm's tar_cmd (deb/pacman/apk/sh/freebsd payloads); needs GNU --sort/--mtime
#   - ar:   fpm's ar_cmd (assembles the .deb ar archive)
#   - lzip: electron-builder's tar.lz archive target (targets/archive.ts)
# electron-builder puts bin/ first on PATH for fpm (FpmTarget.ts) and calls bin/lzip directly.
# "formula:bin1 bin2" entries. Keep in sync with EXPECTED_BINS in assets/verify-bundle.sh.
FORMULA_BINS=(
    "gnu-tar:gtar"
    "lzip:lzip"
    "binutils:ar"
)

FORMULAS=()
for entry in "${FORMULA_BINS[@]}"; do
    FORMULAS+=("${entry%%:*}")
done

# Oldest macOS the bundle must run on. Homebrew bottles inherit the runner's
# OS as their minimum (electron-builder#10084), so verify-bundle.sh fails the
# build if anything in the bundle requires a newer macOS than this.
MAX_MINOS="15.0"

echo "🛠️  linux-tools-mac macOS bundle"
echo "   Arch:   $ARCH"
echo "   macOS:  $(sw_vers -productVersion)"
echo "   Xcode:  $XCODE_VER"
echo "   Output: $OUTPUT_DIR"

### ================================
### CLEAN
### ================================
rm -rf "$TMP_DIR"
mkdir -p "$BIN_DIR" "$LIB_DIR"
: > "$DEP_FORMULAS_FILE"

### ================================
### INSTALL DEPENDENCIES
### ================================
echo ""
echo "📦 Installing brew formulas: ${FORMULAS[*]}"
brew install "${FORMULAS[@]}"

### ================================
### MACH-O HELPERS
### ================================
is_macho() {
    file -b "$1" 2>/dev/null | grep -q '^Mach-O'
}

is_system_lib() {
    [[ "$1" == /usr/lib/* || "$1" == /System/* ]]
}

# Dylibs a Mach-O file loads (load commands only, not its own install name)
macho_deps() {
    otool -l "$1" 2>/dev/null | awk '
        /cmd LC_(LOAD_DYLIB|LOAD_WEAK_DYLIB|REEXPORT_DYLIB|LAZY_LOAD_DYLIB|LOAD_UPWARD_DYLIB)$/ { f = 1; next }
        f && $1 == "name" { print $2; f = 0 }'
}

macho_rpaths() {
    otool -l "$1" 2>/dev/null | awk '/cmd LC_RPATH$/ { f = 1; next } f && $1 == "path" { print $2; f = 0 }'
}

# Resolve a load-command path the way dyld would, relative to the ORIGINAL
# (Homebrew) file that references it. Prints the real path, or nothing.
resolve_dep() {
    local dep="$1" origin="$2"
    local origin_dir candidate rp
    origin_dir="$(dirname "$origin")"
    case "$dep" in
        @loader_path/* | @executable_path/*)
            candidate="${origin_dir}/${dep#*/}"
            [[ -e "$candidate" ]] && realpath "$candidate"
            ;;
        @rpath/*)
            while read -r rp; do
                rp="${rp/#@loader_path/$origin_dir}"
                rp="${rp/#@executable_path/$origin_dir}"
                candidate="${rp}/${dep#@rpath/}"
                if [[ -e "$candidate" ]]; then
                    realpath "$candidate"
                    return 0
                fi
            done < <(macho_rpaths "$origin")
            ;;
        /*)
            [[ -e "$dep" ]] && realpath "$dep"
            ;;
    esac
    return 0
}

# Homebrew formula that owns a Cellar path (for licenses / VERSION.txt)
formula_of() {
    sed -n 's#.*/Cellar/\([^/]*\)/.*#\1#p' <<< "$1"
}

### ================================
### COPY BINARIES
### ================================
echo ""
echo "📋 Copying binaries..."

# bundled file -> original Homebrew file, so deps resolve against the original location
ORIGINS_FILE="${TMP_DIR}/origins.txt"
: > "$ORIGINS_FILE"

for entry in "${FORMULA_BINS[@]}"; do
    formula="${entry%%:*}"
    bins="${entry#*:}"
    prefix="$(brew --prefix "$formula")"
    for bin in $bins; do
        src="$prefix/bin/$bin"
        if [[ ! -e "$src" ]]; then
            echo "  ❌ $formula/$bin not found at $src"
            exit 1
        fi
        echo "  ➕ $formula/$bin"
        cp -L "$src" "$BIN_DIR/$bin"
        chmod u+w,a+x "$BIN_DIR/$bin"
        echo "$BIN_DIR/$bin	$(realpath "$src")" >> "$ORIGINS_FILE"
    done
done

# fpm's ar_cmd probes `ar` then `gar`. Keep the historical gar name as a free
# symlink so the probe order behaves exactly as before.
ln -s ar "$BIN_DIR/gar"
echo "  🔗 gar -> ar"

### ================================
### COLLECT DYLIB DEPENDENCIES
### ================================
echo ""
echo "📚 Collecting dylib dependencies..."

collect_deps() {
    local file="$1" origin="$2"
    local dep resolved name dest
    is_macho "$file" || return 0
    while read -r dep; do
        is_system_lib "$dep" && continue
        resolved="$(resolve_dep "$dep" "$origin")"
        if [[ -z "$resolved" ]]; then
            echo "  ❌ $(basename "$file"): cannot resolve $dep (from $origin)"
            exit 1
        fi
        name="$(basename "$dep")"
        dest="$LIB_DIR/$name"
        [[ -f "$dest" ]] && continue
        echo "    📥 $name  <- $resolved"
        cp -L "$resolved" "$dest"
        chmod u+w "$dest"
        formula_of "$resolved" >> "$DEP_FORMULAS_FILE"
        echo "$dest	$resolved" >> "$ORIGINS_FILE"
        collect_deps "$dest" "$resolved"
    done < <(macho_deps "$file")
}

for bin in "$BIN_DIR"/*; do
    [[ -L "$bin" ]] && continue
    origin="$(awk -F'\t' -v f="$bin" '$1 == f { print $2 }' "$ORIGINS_FILE")"
    echo "  🔍 bin/$(basename "$bin")"
    collect_deps "$bin" "$origin"
done

### ================================
### PATCH DYLIB REFERENCES
### ================================
echo ""
echo "🔧 Patching dylib references..."

patch_macho() {
    local file="$1" is_lib="$2"
    local dep name new_path it_err
    is_macho "$file" || return 0

    if [[ "$is_lib" == "true" ]]; then
        install_name_tool -id "@loader_path/$(basename "$file")" "$file"
    fi

    while read -r dep; do
        is_system_lib "$dep" && continue
        name="$(basename "$dep")"
        [[ -f "$LIB_DIR/$name" ]] || continue
        if [[ "$is_lib" == "true" ]]; then
            new_path="@loader_path/$name"
        else
            new_path="@loader_path/../lib/$name"
        fi
        [[ "$dep" == "$new_path" ]] && continue
        it_err="$(install_name_tool -change "$dep" "$new_path" "$file" 2>&1)" \
            || { echo "  ❌ patch failed [$(basename "$file")] $dep: $it_err"; exit 1; }
    done < <(macho_deps "$file")
}

for bin in "$BIN_DIR"/*; do
    [[ -L "$bin" ]] && continue
    echo "  🔁 bin/$(basename "$bin")"
    patch_macho "$bin" "false"
done

for lib in "$LIB_DIR"/*; do
    [[ -f "$lib" ]] || continue
    echo "  🔁 lib/$(basename "$lib")"
    patch_macho "$lib" "true"
done

### ================================
### STRIP SYMBOLS
### ================================
echo ""
echo "✂️  Stripping symbols..."
find "$BIN_DIR" "$LIB_DIR" -type f | while read -r f; do
    strip -x "$f" 2>/dev/null || true
done

### ================================
### AD-HOC CODESIGN
### ================================
echo ""
echo "🔏 Code signing..."

# Sign libs first (executables may load them)
find "$LIB_DIR" -type f | while read -r lib; do
    codesign --force --sign - "$lib"
done

find "$BIN_DIR" -type f | while read -r bin; do
    codesign --force --sign - "$bin"
done

### ================================
### LICENSES
### ================================
# License texts come from each formula's pinned upstream source tarball, not the keg: Homebrew only installs
# files named COPYING / LICENSE* / ... into the keg, so e.g. binutils' COPYING3 (the GPLv3 ar/libbfd/libsframe
# are under) never reaches it. collect-licenses.sh fails the build if a required text (license-files.tsv) is
# missing, and writes LICENSES/MANIFEST.tsv and LICENSES/SOURCES.txt (GPL corresponding-source pointer).
echo ""
echo "📄 Collecting licenses from the formulas' source tarballs..."

if ! command -v jq > /dev/null 2>&1; then
    echo "❌ jq is required (brew install jq)"
    exit 1
fi

ALL_FORMULAS=()
while read -r formula; do
    [[ -n "$formula" ]] && ALL_FORMULAS+=("$formula")
done < <({ printf '%s\n' "${FORMULAS[@]}"; sort -u "$DEP_FORMULAS_FILE"; } | awk '!seen[$0]++')

# "<formula> <version> <url> <sha256> <tarball> <license> <formula url>", tab-separated (see collect-licenses.sh)
SOURCES_FILE="${TMP_DIR}/sources.tsv"
: > "$SOURCES_FILE"
for formula in "${ALL_FORMULAS[@]}"; do
    info="$(brew info --json=v2 "$formula")"
    src_version="$(jq -r '.formulae[0].versions.stable // empty' <<< "$info")"
    src_url="$(jq -r '.formulae[0].urls.stable.url // empty' <<< "$info")"
    src_sha256="$(jq -r '.formulae[0].urls.stable.checksum // empty' <<< "$info")"
    src_license="$(jq -r '.formulae[0].license // empty | if type == "string" then . else tojson end' <<< "$info")"
    tap_head="$(jq -r '.formulae[0].tap_git_head // empty' <<< "$info")"
    rb_path="$(jq -r '.formulae[0].ruby_source_path // empty' <<< "$info")"
    if [[ -z "$src_version" || -z "$src_url" || ! "$src_sha256" =~ ^[0-9a-f]{64}$ ]]; then
        echo "  ❌ $formula: brew info has no stable source url / sha256"
        exit 1
    fi
    formula_url="unknown"
    if [[ -n "$tap_head" && -n "$rb_path" ]]; then
        formula_url="https://github.com/Homebrew/homebrew-core/blob/${tap_head}/${rb_path}"
    fi
    # Downloads the source tarball and checks it against the formula's sha256
    brew fetch --build-from-source "$formula"
    tarball="$(brew --cache --build-from-source "$formula")"
    echo "  📦 $formula $src_version: $src_url"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$formula" "$src_version" "$src_url" "$src_sha256" "$tarball" \
        "$src_license" "$formula_url" >> "$SOURCES_FILE"
done

bash "$ROOT/assets/collect-licenses.sh" --bundle-dir "$BUNDLE_DIR" --origins "$ORIGINS_FILE" --sources "$SOURCES_FILE"
# Fail before archiving if any binary lacks its license (the test step runs this again on the archive)
bash "$ROOT/assets/verify-bundle-licenses.sh" --bundle-dir "$BUNDLE_DIR"

### ================================
### VERSION.txt
### ================================
echo ""
echo "📝 Writing VERSION.txt..."
{
    echo "platform: darwin"
    echo "arch: $ARCH"
    echo "built_on: macOS $(sw_vers -productVersion), Xcode $XCODE_VER"
    echo "min_macos: $MAX_MINOS"
    echo "created_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo ""
    for formula in "${ALL_FORMULAS[@]}"; do
        ver="$(brew list --versions "$formula" | awk '{print $NF}')"
        echo "$formula: ${ver:-unknown}"
    done
} > "$BUNDLE_DIR/VERSION.txt"
cat "$BUNDLE_DIR/VERSION.txt"

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

bash "$ROOT/assets/test.sh" --bundle-dir "$VERIFY_DIR/linux-tools-mac" --max-minos "$MAX_MINOS"

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
