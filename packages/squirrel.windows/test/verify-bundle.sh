#!/usr/bin/env bash
# Checks a squirrel.windows bundle (the zip build.ps1 produces, or its extracted contents):
#   - the bundle root holds only electron-winstaller/ and LICENSES/ (no stray build output such as
#     the Squirrel nupkg, which earlier releases swept in from build\artifacts)
#   - electron-winstaller/vendor/ has every file electron-builder uses, and no Squirrel.com
#   - LICENSES/ has the license files build.ps1 takes from its build inputs (e.g. NuGet's NOTICES.txt)
#   - every binary has its license files (scripts/verify-licenses.sh, LICENSES/MANIFEST.tsv)
#
# Run: bash packages/squirrel.windows/test/verify-bundle.sh <squirrel.windows-*.zip | extracted bundle dir>
# Exits 1 naming every problem, 2 on usage errors.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"
GUARD="$REPO_ROOT/scripts/verify-licenses.sh"

# Files electron-builder (electron-builder-squirrel-windows) runs or copies from the vendor dir
REQUIRED_VENDOR_FILES=(
    Squirrel.exe Squirrel-Mono.exe SyncReleases.exe Setup.exe StubExecutable.exe WriteZipToSetup.exe
    nuget.exe
    7z.exe 7z.dll 7z-x64.exe 7z-x64.dll 7z-arm64.exe 7z-arm64.dll
    LICENSE 7z-LICENSE.txt
)
# License files build.ps1 copies from its build inputs. The license check needs only one non-empty
# file per component, so it would not notice NOTICES.txt missing next to NuGet's committed LICENSE.txt.
REQUIRED_LICENSE_FILES=(
    squirrel-windows/COPYING semver/LICENSE.md 7-zip/License.txt nuget-commandline/NOTICES.txt
)

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <squirrel.windows-*.zip | extracted bundle dir>" >&2
    exit 2
fi

WORK=""
cleanup() { [[ -n "$WORK" ]] && rm -rf "$WORK"; }
trap cleanup EXIT

if [[ -d "$1" ]]; then
    BUNDLE="$1"
elif [[ -f "$1" ]]; then
    WORK="$(mktemp -d "${TMPDIR:-/tmp}/squirrel-bundle.XXXXXX")"
    BUNDLE="$WORK/bundle"
    mkdir "$BUNDLE"
    if command -v unzip >/dev/null 2>&1; then
        unzip -q "$1" -d "$BUNDLE" || { echo "❌ Cannot extract $1" >&2; exit 2; }
    elif command -v 7z >/dev/null 2>&1; then
        # 7z.exe on Windows (Git Bash) needs Windows paths; MSYS does not convert the one inside -o<dir>
        out_dir="$BUNDLE" archive="$1"
        if command -v cygpath >/dev/null 2>&1; then
            out_dir="$(cygpath -w "$BUNDLE")" archive="$(cygpath -w "$1")"
        fi
        7z x -y -bd "-o$out_dir" "$archive" >/dev/null || { echo "❌ Cannot extract $1" >&2; exit 2; }
    else
        echo "❌ Need unzip or 7z to extract $1" >&2
        exit 2
    fi
else
    echo "❌ Not a file or directory: $1" >&2
    exit 2
fi

FAIL=0
fail() {
    echo "  ✗ $1"
    FAIL=$((FAIL + 1))
}

echo "🔍 Checking the squirrel.windows bundle in $1"

# --- Bundle root: only electron-winstaller/ and LICENSES/ ---
while IFS= read -r -d '' entry; do
    name="${entry##*/}"
    case "$name" in
        electron-winstaller|LICENSES) [[ -d "$entry" ]] || fail "$name: expected a directory at the bundle root" ;;
        *) fail "$name: unexpected entry at the bundle root (only electron-winstaller/ and LICENSES/ belong there)" ;;
    esac
done < <(find "$BUNDLE" -mindepth 1 -maxdepth 1 -print0)

# --- Files that must not ship ---
while IFS= read -r -d '' file; do
    fail "${file#"$BUNDLE"/}: must not ship (stray Squirrel nupkg)"
done < <(find "$BUNDLE" -type f -iname '*.nupkg' -print0)
while IFS= read -r -d '' file; do
    fail "${file#"$BUNDLE"/}: must not ship (Squirrel.com is a renamed Visual Studio devenv.com that electron-builder never runs)"
done < <(find "$BUNDLE" -iname 'Squirrel.com' -print0)

# --- Files electron-builder needs ---
VENDOR="$BUNDLE/electron-winstaller/vendor"
for f in "${REQUIRED_VENDOR_FILES[@]}"; do
    [[ -s "$VENDOR/$f" ]] || fail "electron-winstaller/vendor/$f: missing or empty"
done

# --- Licenses ---
for f in "${REQUIRED_LICENSE_FILES[@]}"; do
    [[ -s "$BUNDLE/LICENSES/$f" ]] || fail "LICENSES/$f: missing or empty"
done
if ! bash "$GUARD" "$BUNDLE"; then
    fail "license check failed (see above)"
fi

if [[ "$FAIL" -gt 0 ]]; then
    echo "❌ squirrel.windows bundle check failed ($FAIL problem(s))"
    exit 1
fi
echo "✓ squirrel.windows bundle OK"
