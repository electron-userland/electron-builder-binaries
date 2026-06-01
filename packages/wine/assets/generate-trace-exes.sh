#!/usr/bin/env bash
set -exo pipefail

echo "🧪 Electron Builder EXE discovery"
echo "--------------------------------"

# ------------------------------------------------------------
# Config
# ------------------------------------------------------------

BASE_URL="https://github.com/electron-userland/electron-builder-binaries/releases/download/win-codesign@1.1.0"

TMP_ROOT="$(mktemp -d)"
DOWNLOAD_DIR="$TMP_ROOT/downloads"
UNPACK_DIR="$TMP_ROOT/unpacked"
OUT_FILE="$TMP_ROOT/exe-list.txt"

mkdir -p "$DOWNLOAD_DIR" "$UNPACK_DIR"

echo "📂 Temp dir: $TMP_ROOT"
echo "📄 Output:   $OUT_FILE"
echo

# ------------------------------------------------------------
# filename | sha256
# ------------------------------------------------------------

ARCHIVES="
windows-kits-bundle-10_0_26100_0.zip 284f18a2fde66e6ecfbefc3065926c9bfdf641761a9e6cd2bd26e18d1e328bf7
win-codesign-windows-x64.zip        6e5dcc5d7af7c00a7387e2101d1ad986aef80e963a3526da07bd0e65de484c30
rcedit-windows-2_0_0.zip            c66591ebe0919c60231f0bf79ff223e6504bfa69bc13edc1fa8bfc6177b73402
"

# ------------------------------------------------------------
# Download + verify + unpack
# ------------------------------------------------------------

echo "$ARCHIVES" | while read NAME SHA; do
  [ -z "$NAME" ] && continue

  URL="$BASE_URL/$NAME"
  DEST="$DOWNLOAD_DIR/$NAME"
  OUT="$UNPACK_DIR/${NAME%.zip}"

  echo "⬇️  Fetching $NAME"
  curl -L --retry 3 --retry-delay 2 --progress-bar "$URL" -o "$DEST"

  echo "🔍 Verifying SHA-256"
  ACTUAL="$(shasum -a 256 "$DEST" | awk '{print $1}')"

  if [ "$ACTUAL" != "$SHA" ]; then
    echo "❌ CHECKSUM FAILURE: $NAME"
    echo "   Expected: $SHA"
    echo "   Actual:   $ACTUAL"
    exit 1
  fi

  echo "✅ Verified"

  echo "📦 Unpacking"
  mkdir -p "$OUT"
  unzip -q "$DEST" -d "$OUT"
  echo
done

# ------------------------------------------------------------
# Discover .exe files
# ------------------------------------------------------------

echo "🔎 Scanning for Windows executables"
echo "----------------------------------"

find "$UNPACK_DIR" -type f -iname "*.exe" \
  | sed 's|^.*/||' \
  | sort -u \
  | tee "$OUT_FILE"

echo
echo "🎉 EXE discovery complete"
echo "📄 File: $OUT_FILE"

# Print path so caller can capture it
echo
echo "EXE_LIST_FILE=$OUT_FILE"
