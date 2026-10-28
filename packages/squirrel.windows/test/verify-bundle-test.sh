#!/usr/bin/env bash
# Self-test for verify-bundle.sh and the committed license layout (licenses/): builds stand-in bundles
# laid out like build.ps1 lays them out (vendor "binaries" are just the PE magic bytes; the license files
# build.ps1 takes from its build inputs or downloads per licenses/UPSTREAM.tsv are stand-in text) and checks
# the right ones pass and fail. The download step itself is tested by upstream-licenses-test.ps1.
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
# The license files build.ps1 copies from its build inputs rather than downloading them
BUILD_LICENSES="squirrel-windows/COPYING semver/LICENSE.md 7-zip/License.txt nuget-commandline/NOTICES.txt"

pe()   { mkdir -p "$(dirname "$1")"; printf 'MZ\220\000\003\000\000\000padding' > "$1"; }
text() { mkdir -p "$(dirname "$1")"; printf '%s\n' "${2:-stand-in license text}" > "$1"; }
sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | awk '{print $1}'
}

# stand_in_upstream <bundle>: a stand-in text for every file licenses/UPSTREAM.tsv lists, and the bundle's
# LICENSES/UPSTREAM.tsv with their SHA-256s (what build.ps1 checks each download against)
stand_in_upstream() {
    local d="$1" line c v f _sha rest
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        case "$line" in ''|'#'*) printf '%s\n' "$line"; continue ;; esac
        IFS=$'\t' read -r c v f _sha rest <<< "$line"
        text "$d/LICENSES/$c/$f" "stand-in $c $f"
        printf '%s\t%s\t%s\t%s\t%s\n' "$c" "$v" "$f" "$(sha256_of "$d/LICENSES/$c/$f")" "$rest"
    done < "$LICENSES_SRC/UPSTREAM.tsv" > "$d/LICENSES/UPSTREAM.tsv.new"
    mv "$d/LICENSES/UPSTREAM.tsv.new" "$d/LICENSES/UPSTREAM.tsv"
}

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
    mkdir -p "$d/LICENSES"
    cp "$LICENSES_SRC/MANIFEST.tsv" "$LICENSES_SRC/SOURCES.md" "$d/LICENSES/"
    stand_in_upstream "$d"
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
expect fail "a missing downloaded license directory fails" "$b" "LICENSES/wtl/: missing" \
    "LICENSES/wtl/CPL.TXT: missing or empty \(listed in LICENSES/UPSTREAM.tsv\)"

# simplejson keeps LICENSE.txt, so only the UPSTREAM.tsv check notices its NOTICE.txt is gone
b=$(new_bundle no-simplejson-notice)
rm "$b/LICENSES/simplejson/NOTICE.txt"
expect fail "a missing downloaded license file of a component with other files fails" "$b" \
    "LICENSES/simplejson/NOTICE.txt: missing or empty \(listed in LICENSES/UPSTREAM.tsv\)"

b=$(new_bundle changed-cpl)
printf 'not the CPL\n' > "$b/LICENSES/wtl/CPL.TXT"
expect fail "a downloaded license file whose SHA-256 differs from UPSTREAM.tsv fails" "$b" \
    "LICENSES/wtl/CPL.TXT: SHA-256 differs from LICENSES/UPSTREAM.tsv"

b=$(new_bundle crlf-upstream)
sed 's/$/\r/' "$b/LICENSES/UPSTREAM.tsv" > "$b/LICENSES/UPSTREAM.tsv.crlf"
mv "$b/LICENSES/UPSTREAM.tsv.crlf" "$b/LICENSES/UPSTREAM.tsv"
expect pass "an UPSTREAM.tsv with CRLF line endings (a Windows checkout) passes" "$b" "squirrel.windows bundle OK"

b=$(new_bundle no-upstream)
rm "$b/LICENSES/UPSTREAM.tsv"
expect fail "a missing UPSTREAM.tsv fails" "$b" "LICENSES/UPSTREAM.tsv: missing or empty"

b=$(new_bundle empty-upstream)
grep '^#' "$LICENSES_SRC/UPSTREAM.tsv" > "$b/LICENSES/UPSTREAM.tsv"
expect fail "an UPSTREAM.tsv that lists no file fails" "$b" "LICENSES/UPSTREAM.tsv: lists no license files"

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
