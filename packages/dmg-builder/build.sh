#!/bin/bash
set -euo pipefail

# CONFIG
PYTHON_VERSION="3.14.2"
# https://github.com/dmgbuild/dmgbuild — base: v1.6.7
# commit 75c8a6c7835c5b73dfd4510d92a8f357f93a5fbf
DMGBUILD_VERSION_OR_HASH="75c8a6c"

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
OUTPUT_DIR="${ROOT}/out/dmg-builder"

# Lowest macOS we promise to support
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-11.0}"

rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

# ─── Homebrew quarantine/avoidance ─────────────────────────────────────────────────
sanitize_path() {
  local IFS=':' p out=()
  for p in $PATH; do
    case "$p" in
      /usr/local/*|/opt/homebrew/*) ;;   # drop
      *) out+=("$p") ;;
    esac
  done
  ( IFS=':'; echo "${out[*]}" )
}
export PATH="$(sanitize_path)"
unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH \
      LIBRARY_PATH DYLD_LIBRARY_PATH DYLD_FALLBACK_LIBRARY_PATH \
      PKG_CONFIG_PATH PKG_CONFIG_LIBDIR \
      SDKROOT HOMEBREW_PREFIX HOMEBREW_CELLAR HOMEBREW_REPOSITORY

# Force clang to ignore /usr/local and /opt/homebrew even if a default search path puts them back. -isysroot pins headers to the SDK only.
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
export CFLAGS="${CFLAGS:-} -isysroot ${SDK_PATH} -nostdinc -isystem ${SDK_PATH}/usr/include -mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET}"
export LDFLAGS="${LDFLAGS:-} -isysroot ${SDK_PATH} -Wl,-syslibroot,${SDK_PATH} -mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET}"

ARCHS=""

usage() {
  echo "Usage: $0 [--arch <arm64|x86_64>] [--arch <...>]"
  echo "  --arch   Target architecture (may be repeated; defaults to current machine arch)"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch) ARCHS="${ARCHS:+$ARCHS }$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; usage ;;
  esac
done

ARCHS="${ARCHS:-$(uname -m)}"

for ARCH in $ARCHS; do
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🏗️  Building Python runtime for ${ARCH}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  bash "$ROOT/assets/build-python-runtime.sh" \
    --root "$ROOT" \
    --output-dir "$OUTPUT_DIR" \
    --python-version "$PYTHON_VERSION" \
    --dmgbuild-version "$DMGBUILD_VERSION_OR_HASH" \
    --codesign-identity "-" \
    --arch "${ARCH}"
done

# ─── Post-build verification ─────────────────────────────────────────────
# Refuse to publish an artifact that references Homebrew paths or whose embedded minOS is newer than our deployment target.
echo ""
echo "🔎 Verifying artifact has no Homebrew leaks and minos<=${MACOSX_DEPLOYMENT_TARGET}"

bad=0
FILELIST="$(mktemp)"
find "${OUTPUT_DIR}" \( -name '*.dylib' -o -name '*.so' -o -perm -u+x -type f \) -print0 > "$FILELIST"
while IFS= read -r -d '' f; do
  # Only inspect Mach-O files
  file "$f" | grep -qE 'Mach-O|dynamically linked' || continue

  if otool -L "$f" 2>/dev/null | grep -E '/usr/local/|/opt/homebrew/' >/tmp/leak.$$; then
    echo "❌ Homebrew dependency in $f:"
    sed 's/^/    /' /tmp/leak.$$
    bad=1
  fi

  minos=$(otool -l "$f" 2>/dev/null \
            | awk '/LC_BUILD_VERSION|LC_VERSION_MIN_MACOSX/{f=1} f && /minos|version/{print $2; f=0}' \
            | head -n1)
  if [ -n "${minos:-}" ]; then
    # numeric compare on "X.Y"
    awk -v a="$minos" -v b="$MACOSX_DEPLOYMENT_TARGET" \
        'BEGIN{split(a,A,"."); split(b,B,"."); \
               if (A[1]+0>B[1]+0 || (A[1]+0==B[1]+0 && A[2]+0>B[2]+0)) exit 1}' \
      || { echo "❌ $f has minos=$minos > ${MACOSX_DEPLOYMENT_TARGET}"; bad=1; }
  fi
done < "$FILELIST"

rm -f /tmp/leak.$$ "$FILELIST"
if [ "$bad" -ne 0 ]; then
  echo "🛑 Build rejected — fix the leaks above before publishing."
  exit 1
fi
echo "✅ Artifact is clean."
