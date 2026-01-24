#!/usr/bin/env bash
set -euo pipefail

# ----------------------------
# Configuration for ./assets build scripts
# ----------------------------
export OSSLSIGNCODE_VER="${OSSLSIGNCODE_VER:-2.11}"
export RCEDIT_VERSION="${RCEDIT_VERSION:-2.0.0}"
export PLATFORM_ARCH="${PLATFORM_ARCH:-x86_64}"
# ----------------------------

CWD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

OS_TARGET=${OS_TARGET:-$(uname | tr '[:upper:]' '[:lower:]')}

if [ "$OS_TARGET" = "linux" ]; then
    echo "Detected Linux target."
    
    bash "$CWD/assets/build-linux.sh"
    
elif [ "$OS_TARGET" = "darwin" ]; then
    echo "Detected macOS target."
    
    bash "$CWD/assets/build-mac.sh"
    
else
    echo "Assuming Windows target."
    
    bash "$CWD/assets/build-win-ossl.sh" # must be first, for now? I think install prefix dest wipes out dir
    bash "$CWD/assets/build-win-kits.sh"
    bash "$CWD/assets/build-win-rcedit.sh"
    
fi
