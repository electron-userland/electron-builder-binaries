#!/usr/bin/env bash
# Self-test for verify-bundle.sh and the committed license layout (licenses/): builds stand-in bundles
# laid out like build.ps1 lays them out (vendor "binaries" are just the PE magic bytes; the license files
# build.ps1 takes from its build inputs are stand-in text) and checks the right ones pass and fail.
# Portable bash: runs on Linux, macOS (bash 3.2) and Git Bash on Windows.
# Run: bash packages/squirrel.windows/test/verify-bundle-test.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFY="$HERE/verify-bundle.sh"
LICENSES_SRC="$HERE/../licenses"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/verify-bundle-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

VENDOR_BINARIES="Squirrel.exe Squirrel-Mono.exe SyncReleases.exe Setup.exe StubExecutable.exe WriteZipToSetup.exe
nuget.exe 7z.exe 7z.dll 7z-x64.exe 7z-x64.dll 7z-arm64.exe 7z-arm64.dll"
# The license files build.ps1 copies from its build inputs rather than from licenses/
BUILD_LICENSES="squirrel-windows/COPYING semver/LICENSE.md 7-zip/License.txt nuget-commandline/NOTICES.txt"

pe()   { mkdir -p "$(dirname "$1")"; printf 'MZ\220\000\003\000\000\000padding' > "$1"; }
text() { mkdir -p "$(dirname "$1")"; printf '%s\n' "${2:-stand-in license text}" > "$1"; }

# new_bundle <name>: a complete, valid bundle
new_bundle() {
    local d="$WORK/$1" f
    rm -rf "$d"
    for f in $VENDOR_BINARIES; do pe "$d/electron-winstaller/vendor/$f"; done
    for f in Squirrel.pdb Setup.pdb Squirrel-Mono.pdb SyncReleases.pdb WriteZipToSetup.pdb; do
        text "$d/electron-winstaller/vendor/$f" "Microsoft C/C++ MSF 7.00"
    done
    text "$d/electron-winstaller/vendor/LICENSE"
    text "$d/electron-winstaller/vendor/7z-LICENSE.txt"
    cp -R "$LICENSES_SRC" "$d/LICENSES"
    for f in $BUILD_LICENSES; do text "$d/LICENSES/$f"; done
    echo "$d"
}

failures=0
# expect <pass|fail> <description> <bundle dir or zip> [grep -E pattern the output must match...]
expect() {
    local want="$1" desc="$2" bundle="$3" out rc=0 got pattern
    shift 3
    out="$(bash "$VERIFY" "$bundle" 2>&1)" || rc=$?
    got=pass
    [ "$rc" -eq 0 ] || got=fail
    if [ "$got" != "$want" ]; then
        echo "❌ $desc: expected $want, got $got (exit $rc)"
        printf '%s\n' "$out" | sed 's/^/     /'
        failures=$((failures + 1))
        return 0
    fi
    for pattern in "$@"; do
        if ! printf '%s\n' "$out" | grep -E -q -- "$pattern"; then
            echo "❌ $desc: output does not match /$pattern/"
            printf '%s\n' "$out" | sed 's/^/     /'
            failures=$((failures + 1))
            return 0
        fi
    done
    echo "✓ $desc"
}

# --- The committed layout covers every binary the bundle ships ---
b=$(new_bundle valid)
expect pass "complete bundle passes" "$b" "All 13 binaries have license files"

# --- Stray build output ---
b=$(new_bundle nupkg)
printf 'PK\003\004' > "$b/squirrel.windows.2.0.1.nupkg"
expect fail "the Squirrel nupkg at the bundle root fails" "$b" \
    "squirrel.windows.2.0.1.nupkg: unexpected entry at the bundle root" "squirrel.windows.2.0.1.nupkg: must not ship"

b=$(new_bundle nupkg-nested)
printf 'PK\003\004' > "$b/electron-winstaller/Squirrel.nupkg"
expect fail "a nupkg anywhere in the bundle fails" "$b" "electron-winstaller/Squirrel.nupkg: must not ship"

b=$(new_bundle squirrel-com)
pe "$b/electron-winstaller/vendor/Squirrel.com"
expect fail "Squirrel.com fails" "$b" "vendor/Squirrel.com: must not ship"

# --- Missing files ---
b=$(new_bundle no-squirrel)
rm "$b/electron-winstaller/vendor/Squirrel.exe"
expect fail "a missing vendor binary fails" "$b" "vendor/Squirrel.exe: missing or empty" \
    "Squirrel.exe: listed in LICENSES/MANIFEST.tsv"

b=$(new_bundle no-vendor-license)
rm "$b/electron-winstaller/vendor/7z-LICENSE.txt"
expect fail "a missing vendor/7z-LICENSE.txt fails" "$b" "vendor/7z-LICENSE.txt: missing or empty"

# --- Licenses ---
for f in $BUILD_LICENSES; do
    b=$(new_bundle "no-${f%%/*}")
    rm "$b/LICENSES/$f"
    expect fail "a missing LICENSES/$f (copied by build.ps1) fails" "$b" "LICENSES/$f: missing or empty"
done

b=$(new_bundle empty-copying)
: > "$b/LICENSES/squirrel-windows/COPYING"
expect fail "an empty license file of a component with no other file fails" "$b" \
    "LICENSES/squirrel-windows/COPYING: missing or empty" "LICENSES/squirrel-windows/: has no non-empty license file"

b=$(new_bundle no-wtl)
rm -r "$b/LICENSES/wtl"
expect fail "a missing committed license directory fails" "$b" "LICENSES/wtl/: missing"

b=$(new_bundle unlisted)
pe "$b/electron-winstaller/vendor/rcedit.exe"
expect fail "an unlisted binary fails" "$b" "electron-winstaller/vendor/rcedit.exe: pe binary not listed"

b=$(new_bundle no-manifest)
rm "$b/LICENSES/MANIFEST.tsv"
expect fail "a missing MANIFEST.tsv fails" "$b" "LICENSES/MANIFEST.tsv is missing"

# --- Zip input (when a zip tool is available) ---
b=$(new_bundle zipped)
zip_made=0
if command -v 7z >/dev/null 2>&1; then
    (cd "$b" && 7z a -tzip -bd "$WORK/bundle.zip" ./* >/dev/null) && zip_made=1
elif command -v zip >/dev/null 2>&1; then
    (cd "$b" && zip -q -r "$WORK/bundle.zip" .) && zip_made=1
fi
if [ "$zip_made" = 1 ]; then
    expect pass "a zip of a complete bundle passes" "$WORK/bundle.zip" "squirrel.windows bundle OK"
else
    echo "- skipped the zip case: no 7z or zip on this system"
fi

# --- Usage errors ---
rc=0
bash "$VERIFY" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 2 ]; then echo "✓ no argument exits 2"; else echo "❌ no argument: expected exit 2, got $rc"; failures=$((failures + 1)); fi
rc=0
bash "$VERIFY" "$WORK/does-not-exist" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 2 ]; then echo "✓ a missing path exits 2"; else echo "❌ missing path: expected exit 2, got $rc"; failures=$((failures + 1)); fi

if [ "$failures" -gt 0 ]; then
    echo "❌ $failures verify-bundle test(s) failed"
    exit 1
fi
echo "✓ All verify-bundle tests passed"
