#!/usr/bin/env bash
# Validates that every pending-release package will land in artifacts-staging/<name>/
# as a directory (not flat files), which is required by changeset-version.js.
#
# Creates one stub file per package under the expected out/<name>/ subdirectory,
# runs compress-artifacts.sh, then runs changeset-version.js in DRY_RUN mode.
# Cleans up after itself — no side effects.
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)
OUT_DIR="$ROOT_DIR/out"
STAGING_DIR="$ROOT_DIR/artifacts-staging"
CHANGESET_JSON="$ROOT_DIR/changeset-status.json"

cleanup() {
  rm -rf "$OUT_DIR" "$STAGING_DIR" "$CHANGESET_JSON"
}
trap cleanup EXIT

stub_relative_path() {
  case "$1" in
    wine)             echo "wine/stub.tar.xz" ;;
    wix)              echo "wix/stub.tar.gz" ;;
    nsis)             echo "nsis/stub.tar.gz" ;;
    fpm)              echo "fpm/stub.7z" ;;
    appimage)         echo "appimage/stub.tar.gz" ;;
    icons)            echo "icons/stub.tar.gz" ;;
    win-codesign)     echo "win-codesign/stub.zip" ;;
    ran)              echo "ran/stub.zip" ;;
    dmg-builder)      echo "dmg-builder/stub.tar.gz" ;;
    linux-tools-mac)  echo "linux-tools-mac/stub.tar.gz" ;;
    squirrel.windows) echo "squirrel.windows/stub.7z" ;;
    *)
      echo "WARNING: unknown package '$1', using default path" >&2
      echo "$1/stub.txt"
      ;;
  esac
}

# Detect pending packages (same query as detect-packages.sh)
cd "$ROOT_DIR"
pnpm changeset status --output "$CHANGESET_JSON" 2>/dev/null || true

if [ ! -s "$CHANGESET_JSON" ]; then
  echo "No pending changesets — nothing to validate."
  exit 0
fi

PACKAGES=$(jq -r '.releases[].name' "$CHANGESET_JSON" | sort -u)

if [ -z "$PACKAGES" ]; then
  echo "No release candidates detected — nothing to validate."
  exit 0
fi

echo "Validating staging structure for: $(echo "$PACKAGES" | tr '\n' ' ')"

# Create stub files
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

for PKG in $PACKAGES; do
  STUB_PATH="$(stub_relative_path "$PKG")"
  FULL_PATH="$OUT_DIR/$STUB_PATH"
  mkdir -p "$(dirname "$FULL_PATH")"
  touch "$FULL_PATH"
  echo "  stub: out/$STUB_PATH"
done

# Run compress-artifacts to copy out/* → artifacts-staging/*
bash "$ROOT_DIR/scripts/compress-artifacts.sh"

# Validate with DRY_RUN (now asserts each staging path is a directory)
DRY_RUN=true node "$ROOT_DIR/scripts/changeset-version.js"

echo "Staging structure validation passed."
