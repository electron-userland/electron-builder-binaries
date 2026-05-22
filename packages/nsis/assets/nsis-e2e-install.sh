#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# NSIS E2E Install + Uninstall Runner
# =============================================================================
# Usage: nsis-e2e-install.sh [--installers-dir PATH]
#
# --installers-dir PATH  Directory containing nsis-e2e-installer-{platform}/ subdirs,
#                        each holding an e2e-installer.exe compiled by that platform.
#                        Defaults to ./installers
#
# Runs install + uninstall for every installer found. Exits with the total
# number of failures (0 = all passed).
# =============================================================================

INSTALLERS_DIR="./installers"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --installers-dir) INSTALLERS_DIR="${2:-}"; shift 2 ;;
        *) echo "❌ Unknown option: $1"; exit 1 ;;
    esac
done

PASS=0
FAIL=0

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  E2E Install + Uninstall — all compiled platforms"
echo "  Installers: $INSTALLERS_DIR"
echo "═══════════════════════════════════════════════════════════════"

shopt -s nullglob
dirs=( "$INSTALLERS_DIR"/nsis-e2e-installer-*/ )
if [[ ${#dirs[@]} -eq 0 ]]; then
    echo "❌ No installer directories found in $INSTALLERS_DIR"
    exit 1
fi

for dir in "${dirs[@]}"; do
    platform="${dir#"$INSTALLERS_DIR"/nsis-e2e-installer-}"
    platform="${platform%/}"
    installer="$dir/e2e-installer.exe"
    install_dir="${TEMP:-/tmp}/NsisE2ETest"

    echo ""
    echo "── $platform ───────────────────────────────────────────────"

    if [ ! -f "$installer" ]; then
        echo "[FAIL] $platform: installer not found at $installer"
        FAIL=$((FAIL + 1))
        continue
    fi

    # Clean any leftover from a previous loop iteration
    rm -rf "$install_dir" 2>/dev/null || true

    # Install (SilentInstall silent is set in the NSI; /S is explicit for clarity)
    if "$installer" /S; then
        echo "[PASS] $platform: install succeeded"
        PASS=$((PASS + 1))
    else
        echo "[FAIL] $platform: installer returned non-zero"
        FAIL=$((FAIL + 1))
        continue
    fi

    # Verify sentinel file
    if [ -f "$install_dir/INSTALLED.txt" ]; then
        echo "[PASS] $platform: INSTALLED.txt created"
        PASS=$((PASS + 1))
    else
        echo "[FAIL] $platform: INSTALLED.txt not found at $install_dir"
        FAIL=$((FAIL + 1))
    fi

    # Uninstall
    UNINSTALLER="$install_dir/Uninstall.exe"
    if [ -f "$UNINSTALLER" ]; then
        "$UNINSTALLER" /S || true
        # NSIS uninstallers copy themselves to TEMP before running; give it a moment to finish
        sleep 2

        if [ ! -f "$install_dir/INSTALLED.txt" ]; then
            echo "[PASS] $platform: INSTALLED.txt removed"
            PASS=$((PASS + 1))
        else
            echo "[FAIL] $platform: INSTALLED.txt still present after uninstall"
            FAIL=$((FAIL + 1))
        fi

        if [ ! -d "$install_dir" ]; then
            echo "[PASS] $platform: install directory removed"
            PASS=$((PASS + 1))
        else
            echo "[FAIL] $platform: install directory still present after uninstall"
            FAIL=$((FAIL + 1))
            rm -rf "$install_dir" 2>/dev/null || true
        fi
    else
        echo "[FAIL] $platform: Uninstall.exe not found at $install_dir"
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "═══════════════════════════════════════════════════════════════"
printf "  Results: %d passed, %d failed\n" "$PASS" "$FAIL"
echo "═══════════════════════════════════════════════════════════════"
echo ""

exit $FAIL
