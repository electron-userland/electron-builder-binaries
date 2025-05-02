#!/usr/bin/env bash
set -ex

FPM_VERSION=1.16.0 OUTPUT_SUBDIR=out/fpm/mac sh ./docker-scripts/fpm.sh
sh ./scripts/linux-tools-mac.sh
sh ./scripts/nsis-mac.sh
sh ./scripts/zstd-win-mac.sh
sh ./scripts/nsis-plugins-TBD.sh
sh ./scripts/appimage-mac.sh
sh ./packages/win-codesign/darwin/build.sh
sh ./packages/wine/wine-mac-ia32-and-x64.sh