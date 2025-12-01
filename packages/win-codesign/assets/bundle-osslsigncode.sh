#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
OSSLSIGNCODE_SRC="${1:-${OSSLSIGNCODE_SRC:-}}"
OUTPUT_DIR="${2:-$ROOT/out/osslsigncode}"
PLATFORM_ARCH="${PLATFORM_ARCH:-$(uname -m)}"
TMP_PREFIX="/tmp/osslsigncode-bundle"

if [[ -z "$OSSLSIGNCODE_SRC" ]]; then
  echo "Usage: $0 /path/to/osslsigncode [output-dir]"
  exit 2
fi

if [[ ! -x "$OSSLSIGNCODE_SRC" ]]; then
  echo "Error: osslsigncode binary not found or not executable: $OSSLSIGNCODE_SRC"
  exit 3
fi

mkdir -p "$OUTPUT_DIR"
rm -rf "$TMP_PREFIX"
INSTALL_DIR="$TMP_PREFIX/install"
BIN_DIR="$INSTALL_DIR/bin"
LIB_DIR="$INSTALL_DIR/lib"
mkdir -p "$BIN_DIR" "$LIB_DIR"

uname_s=$(uname -s)

echo "🛠 Building minimal osslsigncode bundle"
echo "  source binary: $OSSLSIGNCODE_SRC"
echo "  working tmp:   $TMP_PREFIX"
echo "  output dir:    $OUTPUT_DIR"
echo "  install dir:   $INSTALL_DIR"
echo "  platform arch: $PLATFORM_ARCH"

# ================================================================
# Copy binary
echo "  ➕ Copying osslsigncode binary to bundle"
cp -a "$OSSLSIGNCODE_SRC" "$BIN_DIR/osslsigncode"
chmod +x "$BIN_DIR/osslsigncode"


# ================================================================
# Linu
# ================================================================
if [[ "$uname_s" == "Linux" ]]; then
  echo "🐧 Linux detected"

  "$ROOT/bundle-osslsigncode-libs.sh" "$BIN_DIR" "$OUTPUT_DIR"
fi

# ================================================================
# Stripping
# ================================================================
echo "✂ Stripping symbols"
# Only attempt to strip actual files (not symlinks). Use safe flags.
find "$INSTALL_DIR" -type f -print0 | while IFS= read -r -d '' f; do
  # skip small text files and VERSION.txt
  [[ ! -x "$f" && "$f" == *VERSION.txt ]] && continue
  # try to strip (best-effort)
  if command -v strip >/dev/null 2>&1; then
    strip --strip-unneeded "$f" 2>/dev/null || true
  fi
done

# ================================================================
# macOS adhoc signing
# ================================================================
if [[ "$uname_s" == "Darwin" ]]; then
  # macOS ad-hoc signing (best-effort)
  echo "🔏 Code signing binaries and libraries..."
  for f in "$BIN_DIR"/*; do
    /usr/bin/codesign --force --sign - "$f"
  done
  # verify signatures (should not print errors)
  /usr/bin/codesign -v --deep --strict "$BIN_DIR/osslsigncode"
fi

# ================================================================
# VERSION file
# ================================================================
OSSL_VER=$("$BIN_DIR/osslsigncode" --version 2>&1 | head -n1 || true)
{
  echo "osslsigncode: ${OSSL_VER:-unknown}"
  echo "platform: $uname_s"
  echo "created_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
} > "$INSTALL_DIR/VERSION.txt"

# Create entrypoint/launcher for convenience (sets library path at runtime)
WRAPPER="$INSTALL_DIR/osslsigncode"
cat > "$WRAPPER" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$(uname -s)" in
  Darwin)
    # Remove quarantine attribute from the osslsigncode binary if present
    if grep -q "com.apple.quarantine" <<< "$(xattr "$HERE/bin/osslsigncode" 2>/dev/null || true)"; then
        xattr -d com.apple.quarantine "$HERE/bin/osslsigncode" || true
    fi

    export DYLD_FALLBACK_LIBRARY_PATH="$HERE/lib:${DYLD_FALLBACK_LIBRARY_PATH:-}"
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

# ================================================================
# PACKAGING
# ================================================================
ARCHIVE_ARCH_SUFFIX=$(echo ${PLATFORM_ARCH:-$(uname -m)} | tr -d '/' | tr '[:upper:]' '[:lower:]')
ARCHIVE_NAME="win-codesign-$(uname -s | tr A-Z a-z)-$ARCHIVE_ARCH_SUFFIX.zip"

echo "📦 Creating ZIP bundle: $ARCHIVE_NAME"
(
  cd "$INSTALL_DIR"
  zip -r -9 "$OUTPUT_DIR/$ARCHIVE_NAME" . >/dev/null
)

rm -rf "$TMP_PREFIX"

echo "✅ Done!"
echo "Bundle at: $OUTPUT_DIR/$ARCHIVE_NAME"
