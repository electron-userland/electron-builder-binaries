#!/bin/bash
set -e

REPO="dmgbuild"
BASE_TAG="v1.6.7"
TARGET="9614277f759768cfc156a3493dd2b60fae7d63d5"

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BUILD_DIR="$ROOT/build"
cd "$BUILD_DIR"
# if already cloned, just update
if [ -d "$REPO/.git" ]; then
    cd "$REPO"
    git fetch --all
    git checkout "$TARGET"
    cd ..
else
    git clone https://github.com/dmgbuild/dmgbuild.git "$REPO" || true
fi
cd "$REPO"
git fetch --tags

git rev-list --reverse "$BASE_TAG..$TARGET" > "$BUILD_DIR/commits.txt"

mkdir -p "$ROOT/assets/patches"

while read commit; do
    short=$(echo "$commit" | cut -c1-7)
    idx=$(printf "%03d" $(grep -n "$commit" "$BUILD_DIR/commits.txt" | cut -d: -f1))
    git format-patch -1 "$commit" -o "$ROOT/assets/patches/" -N --start-number "$idx" --suffix ".patch" 
done < "$BUILD_DIR/commits.txt"

echo "Generated patches in $ROOT/assets/patches"