#!/bin/bash
set -euo pipefail

# CONFIG
# renovate: datasource=python-version depName=python
PYTHON_VERSION="3.14.10"
# OpenSSL for the _ssl/_hashlib modules, built from source for MACOSX_DEPLOYMENT_TARGET.
# 3.5 is the current LTS line (supported until 2030-04-08).
# renovate: datasource=github-releases depName=openssl/openssl extractVersion=^openssl-(?<version>.+)$
OPENSSL_VERSION="3.5.9"
# https://github.com/dmgbuild/dmgbuild — base: v1.6.7 (no newer release)
# commit cc96fa235365b787ad0d73e4802a1f3953a62b19
# Renovate proposes newer master commits for this hash (the dmgbuild customManager in .github/renovate.json5)
DMGBUILD_VERSION_OR_HASH="cc96fa2"

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
PATH="$(sanitize_path)"
export PATH
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
    --openssl-version "$OPENSSL_VERSION" \
    --dmgbuild-version "$DMGBUILD_VERSION_OR_HASH" \
    --codesign-identity "-" \
    --arch "${ARCH}"
done

# ─── Post-build verification ─────────────────────────────────────────────
# Refuse to publish an artifact that links Homebrew libraries or contains a Mach-O whose minOS is newer than our
# deployment target. This inspects the extracted tarballs, i.e. exactly what ships (the per-arch staging dir is
# wiped by the next arch's build), and fails if there is nothing to inspect.
echo ""
echo "🔎 Verifying artifacts have no Homebrew links and minos<=${MACOSX_DEPLOYMENT_TARGET}"

ARCHIVES=()
while IFS= read -r -d '' a; do ARCHIVES+=("$a"); done < <(find "${OUTPUT_DIR}" -name '*.tar.gz' -print0)
if [ "${#ARCHIVES[@]}" -eq 0 ]; then
  echo "❌ No archives found in ${OUTPUT_DIR}"
  exit 1
fi
bash "$ROOT/assets/verify-bundle.sh" --macos-target "${MACOSX_DEPLOYMENT_TARGET}" "${ARCHIVES[@]}"

# Every binary in what ships must carry its license (LICENSES/MANIFEST.tsv, see assets/collect-licenses.sh)
echo "🔎 Verifying every binary in the artifacts has its license"
LICENSE_CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$LICENSE_CHECK_DIR"' EXIT
for a in "${ARCHIVES[@]}"; do
  d="$(mktemp -d "$LICENSE_CHECK_DIR/bundle.XXXXXX")"
  tar -xzf "$a" -C "$d"
  echo "📦 $(basename "$a")"
  bash "$ROOT/../../scripts/verify-licenses.sh" "$d"
done
echo "✅ Artifact is clean."
