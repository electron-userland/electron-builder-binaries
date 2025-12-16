#!/usr/bin/env bash
set -euo pipefail


BASE_DIR=$(cd "$(dirname "$BASH_SOURCE")" && pwd)
source "$BASE_DIR/utils.sh"


hashArtifact()
{
    ARCHIVE_NAME=$1
    CHECKSUM=$(shasum -a 512 "$ARTIFACTS_DIR/$ARCHIVE_NAME" | xxd -r -p | base64)
    EXPECTED="${2:-$CHECKSUM}"
    if [ "$CHECKSUM" != "$EXPECTED" ]; then
        echo "Checksum for $ARCHIVE_NAME does not match expected checksum"
        echo "Expected: $EXPECTED"
        echo "Actual: $CHECKSUM"
        exit 1
    else
        echo "Checksum for $ARCHIVE_NAME matches expected checksum"
    fi
    echo "$ARCHIVE_NAME: $CHECKSUM" >> "$ARTIFACTS_DIR/checksums.txt"
}

downloadArtifact()
{
    RELEASE_NAME=$1
    ARCHIVE_NAME="$2.7z"
    CHECKSUM=$3
    OUTPUT_NAME="${4:-$2}.7z"
    curl -L https://github.com/electron-userland/electron-builder-binaries/releases/download/$RELEASE_NAME/$ARCHIVE_NAME > "$ARTIFACTS_DIR/$OUTPUT_NAME"
    hashArtifact "$OUTPUT_NAME" "$CHECKSUM"
}


NAMES=(
  fpm
  win-codesign
  appimage
)

for NAME in "${NAMES[@]}"; do
  DESTINATION_DIR="$ARTIFACTS_DIR/$NAME"

  rm -rf "$DESTINATION_DIR"
  cp -a "$BUILD_OUT_DIR/$NAME" "$DESTINATION_DIR"

  for f in "$DESTINATION_DIR"/*; do
    # Skip if no files match
    [[ -e "$f" ]] || continue

    hashArtifact "$NAME/$(basename "$f")"
  done
done

sort "$ARTIFACTS_DIR/checksums.txt" -o "$ARTIFACTS_DIR/checksums.txt"
echo "Artifacts compressed and checksums generated in $ARTIFACTS_DIR"