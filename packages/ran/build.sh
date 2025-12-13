#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

rm -rf "$ROOT/out"
VERSION="v0.1.6" bash "$ROOT/assets/build.sh"