#!/usr/bin/env bash
# CI helper (build-archive.yaml): extracts the archive toolset to ./bundle and the published fpm toolset (the release
# asset electron-builder downloads, checked against its sha256) to ./fpm, in the current directory.
#
# Usage: fetch-test-inputs.sh <archive-*.7z> <fpm platform, e.g. linux-amd64> <fpm asset sha256>
set -euo pipefail

FPM_RELEASE="fpm@2.3.1"
FPM_ASSET_PREFIX="fpm-1.18.0-ruby-3.4.12"

ARCHIVE="${1:?usage: fetch-test-inputs.sh <archive.7z> <fpm platform> <fpm sha256>}"
PLATFORM="${2:?usage: fetch-test-inputs.sh <archive.7z> <fpm platform> <fpm sha256>}"
SHA256="${3:?usage: fetch-test-inputs.sh <archive.7z> <fpm platform> <fpm sha256>}"

SZ=$(command -v 7zz || command -v 7z || command -v 7za || true)
if [ -z "$SZ" ] && command -v apt-get >/dev/null; then
    sudo apt-get update -qq && sudo apt-get install -y -qq p7zip-full >/dev/null
    SZ=$(command -v 7z)
fi
[ -n "$SZ" ] || { echo "❌ 7-Zip not found" >&2; exit 1; }

rm -rf bundle fpm fpm.7z
ls -la "$(dirname "$ARCHIVE")"
"$SZ" x -bd -obundle "$ARCHIVE" >/dev/null
echo "archive toolset: $(du -sh bundle | cut -f1) unpacked from $(basename "$ARCHIVE") ($(wc -c <"$ARCHIVE" | tr -d ' ') bytes)"

url="https://github.com/electron-userland/electron-builder-binaries/releases/download/${FPM_RELEASE}/${FPM_ASSET_PREFIX}-${PLATFORM}.7z"
curl -fsSL --retry 5 --retry-delay 10 "$url" -o fpm.7z
if command -v sha256sum >/dev/null; then actual=$(sha256sum fpm.7z | awk '{print $1}'); else actual=$(shasum -a 256 fpm.7z | awk '{print $1}'); fi
if [ "$actual" != "$SHA256" ]; then
    echo "❌ $url: sha256 $actual, expected $SHA256" >&2
    exit 1
fi
"$SZ" x -bd -ofpm fpm.7z >/dev/null
rm -f fpm.7z
echo "fpm toolset: $FPM_RELEASE $(basename "$url") (sha256 verified)"
