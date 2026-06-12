#!/usr/bin/env bash
set -euo pipefail

# CLI flags take precedence over env vars, env vars over built-in defaults.

CWD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat >&2 << EOF
Usage: $0 [options]
  --arch              Target architecture (default: \$PLATFORM_ARCH or 'x86_64')
  --osslsigncode-ver  osslsigncode version tag (default: \$OSSLSIGNCODE_VER or '2.11')
  --rcedit-version    rcedit release version (default: \$RCEDIT_VERSION or '2.0.0')
  --os-target         Override OS detection: linux, darwin, windows
                      (default: auto-detected via uname)
  --target            Windows subscript to run: ossl, kits, rcedit
                      (repeatable; default: all three)
  -h|--help           Show this help
EOF
    exit 1
}

PLATFORM_ARCH="${PLATFORM_ARCH:-x86_64}"
OSSLSIGNCODE_VER="${OSSLSIGNCODE_VER:-2.11}"
RCEDIT_VERSION="${RCEDIT_VERSION:-2.0.0}"
OS_TARGET="${OS_TARGET:-}"
TARGETS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)             PLATFORM_ARCH="$2";    shift 2 ;;
        --osslsigncode-ver) OSSLSIGNCODE_VER="$2"; shift 2 ;;
        --rcedit-version)   RCEDIT_VERSION="$2";   shift 2 ;;
        --os-target)        OS_TARGET="$2";        shift 2 ;;
        --target)           TARGETS+=("$2");       shift 2 ;;
        -h|--help)          usage ;;
        *)                  echo "❌ Unknown argument: $1" >&2; usage ;;
    esac
done

OS_TARGET="${OS_TARGET:-$(uname | tr '[:upper:]' '[:lower:]')}"

# Export so subscripts can pick these up as env-var fallbacks if invoked standalone
export PLATFORM_ARCH OSSLSIGNCODE_VER RCEDIT_VERSION

if [ "$OS_TARGET" = "linux" ]; then
    echo "Detected Linux target."

    bash "$CWD/assets/build-linux.sh" \
        --arch "${PLATFORM_ARCH}" \
        --osslsigncode-ver "${OSSLSIGNCODE_VER}"

elif [ "$OS_TARGET" = "darwin" ]; then
    echo "Detected macOS target."

    bash "$CWD/assets/build-mac.sh" \
        --arch "${PLATFORM_ARCH}" \
        --osslsigncode-ver "${OSSLSIGNCODE_VER}"

else
    echo "Assuming Windows target."

    # Default to all three when no --target flags were given
    if [[ ${#TARGETS[@]} -eq 0 ]]; then
        TARGETS=(ossl kits rcedit)
    fi

    # must be first — install prefix wipes the output dir
    if [[ " ${TARGETS[*]} " == *" ossl "* ]]; then
        bash "$CWD/assets/build-win-ossl.sh" \
            --arch "${PLATFORM_ARCH}" \
            --osslsigncode-ver "${OSSLSIGNCODE_VER}"
    fi

    if [[ " ${TARGETS[*]} " == *" kits "* ]]; then
        bash "$CWD/assets/build-win-kits.sh"
    fi

    if [[ " ${TARGETS[*]} " == *" rcedit "* ]]; then
        bash "$CWD/assets/build-win-rcedit.sh" \
            --version "${RCEDIT_VERSION}"
    fi

fi
