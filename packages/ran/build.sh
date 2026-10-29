#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

rm -rf "$ROOT/out"
# renovate: datasource=github-releases depName=m3ng9i/ran
VERSION="v0.1.6" bash "$ROOT/assets/build.sh"