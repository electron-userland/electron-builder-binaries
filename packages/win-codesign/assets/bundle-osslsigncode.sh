#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

usage() {
    echo "Usage: $0 --src <path-to-osslsigncode> --licenses-dir <dir> [--lib-dir <dir>] [--output-dir <dir>] [--platform-arch <arch>]" >&2
    echo "  --src           Path to the compiled osslsigncode binary (required)" >&2
    echo "  --licenses-dir  Staged LICENSES/ directory (MANIFEST.tsv + per-component license files, see licenses.sh)" >&2
    echo "                  copied into the bundle as LICENSES/ (required)" >&2
    echo "  --lib-dir       Directory whose contents are copied into the bundle's lib/" >&2
    echo "  --output-dir    Directory to write the final ZIP bundle (default: \$ROOT/out/osslsigncode)" >&2
    echo "  --platform-arch Target architecture label, e.g. amd64, arm64, i386 (default: \$(uname -m))" >&2
    exit 2
}

OSSLSIGNCODE_SRC="${OSSLSIGNCODE_SRC:-}"
EXTRA_LIB_DIR=""
LICENSES_SRC=""
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/out/osslsigncode}"
PLATFORM_ARCH="${PLATFORM_ARCH:-$(uname -m)}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --src)           OSSLSIGNCODE_SRC="$2"; shift 2 ;;
        --lib-dir)       EXTRA_LIB_DIR="$2";    shift 2 ;;
        --licenses-dir)  LICENSES_SRC="$2";     shift 2 ;;
        --output-dir)    OUTPUT_DIR="$2";        shift 2 ;;
        --platform-arch) PLATFORM_ARCH="$2";     shift 2 ;;
        -h|--help) usage ;;
        *) echo "❌ Unknown argument: $1" >&2; usage ;;
    esac
done

if [[ -z "$OSSLSIGNCODE_SRC" ]]; then
    echo "❌ Error: --src is required" >&2
    usage
fi

if [[ -z "$LICENSES_SRC" || ! -f "$LICENSES_SRC/MANIFEST.tsv" ]]; then
    echo "❌ Error: --licenses-dir must point to a staged LICENSES/ directory with a MANIFEST.tsv" >&2
    usage
fi

if [[ ! -x "$OSSLSIGNCODE_SRC" ]]; then
    echo "❌ Error: osslsigncode binary not found or not executable: $OSSLSIGNCODE_SRC" >&2
    exit 3
fi

mkdir -p "$OUTPUT_DIR"

TMP_PREFIX="$(mktemp -d /tmp/osslsigncode-bundle-XXXXXX)"
INSTALL_DIR="$TMP_PREFIX/install"
BIN_DIR="$INSTALL_DIR/bin"
LIB_DIR="$INSTALL_DIR/lib"
mkdir -p "$BIN_DIR" "$LIB_DIR"

# ── Cleanup on exit ───────────────────────────────────────────────────────────
cleanup() {
    rm -rf "$TMP_PREFIX"
}
trap cleanup EXIT

uname_s=$(uname -s)

echo "🛠 Building minimal osslsigncode bundle"
echo "  source binary: $OSSLSIGNCODE_SRC"
echo "  working tmp:   $TMP_PREFIX"
echo "  output dir:    $OUTPUT_DIR"
echo "  install dir:   $INSTALL_DIR"
echo "  platform arch: $PLATFORM_ARCH"

# ── Copy binary ───────────────────────────────────────────────────────────────
echo "  ➕ Copying osslsigncode binary to bundle"
cp -a "$OSSLSIGNCODE_SRC" "$BIN_DIR/osslsigncode"
chmod +x "$BIN_DIR/osslsigncode"

# ── Bundled libraries (OpenSSL + pkcs11prov, from build-mac.sh / build-linux-osslsigncode.sh)
if [[ -n "$EXTRA_LIB_DIR" ]]; then
    echo "  ➕ Copying bundled libraries from $EXTRA_LIB_DIR"
    cp -R "$EXTRA_LIB_DIR"/. "$LIB_DIR"/
fi

# ── Strip symbols ─────────────────────────────────────────────────────────────
echo "✂ Stripping symbols"
find "$INSTALL_DIR" -type f -print0 | while IFS= read -r -d '' f; do
    [[ ! -x "$f" && "$f" == *VERSION.txt ]] && continue
    # Apple's strip would drop the dylibs' exported symbols; they are signed below as built.
    [[ "$uname_s" == "Darwin" && "$f" == "$LIB_DIR"/* ]] && continue
    # build-linux-osslsigncode.sh strips the binary and libraries before setting their RUNPATH.
    [[ "$uname_s" == "Linux" ]] && continue
    if command -v strip >/dev/null 2>&1; then
        strip --strip-unneeded "$f" 2>/dev/null || true
    fi
done

# ── macOS ad-hoc signing ──────────────────────────────────────────────────────
if [[ "$uname_s" == "Darwin" ]]; then
    echo "🔏 Code signing binaries and libraries..."
    while IFS= read -r -d '' f; do
        /usr/bin/codesign --force --sign - "$f"
    done < <(find "$LIB_DIR" -type f -name '*.dylib' -print0)
    for f in "$BIN_DIR"/*; do
        /usr/bin/codesign --force --sign - "$f"
    done
    /usr/bin/codesign -v --deep --strict "$BIN_DIR/osslsigncode"
fi

# ── VERSION file ──────────────────────────────────────────────────────────────
OSSL_VER=$("$BIN_DIR/osslsigncode" --version 2>&1 | head -n1 || true)
{
    echo "osslsigncode: ${OSSL_VER:-unknown}"
    echo "platform: $uname_s"
    echo "created_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
} > "$INSTALL_DIR/VERSION.txt"

# ── Launcher wrapper ──────────────────────────────────────────────────────────
WRAPPER="$INSTALL_DIR/osslsigncode"
cat > "$WRAPPER" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$(uname -s)" in
  Darwin)
    # Gatekeeper also checks quarantined dylibs when they load, so clear lib/ too.
    if grep -q "com.apple.quarantine" <<< "$(xattr -r "$HERE/bin" "$HERE/lib" 2>/dev/null || true)"; then
        xattr -dr com.apple.quarantine "$HERE/bin" "$HERE/lib" 2>/dev/null || true
    fi
    export DYLD_FALLBACK_LIBRARY_PATH="$HERE/lib:${DYLD_FALLBACK_LIBRARY_PATH:-}"
    # Bundled pkcs11prov (libp11) for -pkcs11module signing; must share the bundled libcrypto.
    export OPENSSL_MODULES="$HERE/lib/ossl-modules"
    ;;
  Linux|GNU*)
    export LD_LIBRARY_PATH="$HERE/lib:${LD_LIBRARY_PATH:-}"
    export OPENSSL_MODULES="$HERE/lib/ossl-modules"
    ;;
esac

exec "$HERE/bin/osslsigncode" "$@"
EOF
chmod +x "$WRAPPER"

echo "  - Launch binary via: $WRAPPER --version"
echo "  - Or run: LD_LIBRARY_PATH=$LIB_DIR OPENSSL_MODULES=$LIB_DIR/ossl-modules $BIN_DIR/osslsigncode"

# ── Packaging ─────────────────────────────────────────────────────────────────
ARCHIVE_ARCH_SUFFIX=$(echo "${PLATFORM_ARCH}" | tr -d '/' | tr '[:upper:]' '[:lower:]')
ARCHIVE_NAME="win-codesign-$(uname -s | tr '[:upper:]' '[:lower:]')-$ARCHIVE_ARCH_SUFFIX.zip"

# ── Licenses ──────────────────────────────────────────────────────────────────
# Staged by the caller from the pinned sources (osslsigncode tag, OpenSSL / libp11 tarballs); copied after
# stripping so the strip loop never touches them. The caller checks the zip with scripts/verify-licenses.sh.
echo "📄 Adding LICENSES/"
cp -R "$LICENSES_SRC" "$INSTALL_DIR/LICENSES"

echo "📦 Creating ZIP bundle: $ARCHIVE_NAME"
(
    cd "$INSTALL_DIR"
    zip -r -9 "$OUTPUT_DIR/$ARCHIVE_NAME" . >/dev/null
)

echo "✅ Done!"
echo "Bundle at: $OUTPUT_DIR/$ARCHIVE_NAME"
