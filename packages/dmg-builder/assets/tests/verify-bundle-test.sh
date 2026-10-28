#!/usr/bin/env bash
# Self-test for assets/verify-bundle.sh: builds tiny Mach-O fixtures with
# known minos values / Homebrew links and checks the guard accepts and rejects
# the right ones. Runs on macOS (needs clang, otool, tar).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFY="$HERE/../verify-bundle.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SDK="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"
echo 'int main(void) { return 0; }' > "$WORK/main.c"
echo 'int fake(void) { return 0; }' > "$WORK/lib.c"

cc_exe() { # <out> <minos> [arch]
    clang -isysroot "$SDK" -arch "${3:-$ARCH}" -mmacosx-version-min="$2" "$WORK/main.c" -o "$1"
}
cc_dylib() { # <out> <minos> [extra clang args...]
    local out="$1" minos="$2"; shift 2
    clang -isysroot "$SDK" -arch "$ARCH" -mmacosx-version-min="$minos" -dynamiclib "$WORK/lib.c" -o "$out" "$@"
}
new_bundle() { # <name> -> path of a bundle dir with a python3 built for 11.0 and a .py file
    local d="$WORK/$1"
    mkdir -p "$d/python/bin" "$d/python/lib"
    cc_exe "$d/python/bin/python3" 11.0
    echo 'print("hi")' > "$d/python/lib/site.py"
    echo "$d"
}

failures=0
expect() { # <pass|fail> <description> <grep pattern for output, or ""> <verify args...>
    local want="$1" desc="$2" pattern="$3"; shift 3
    local out rc=0
    out="$(bash "$VERIFY" "$@" 2>&1)" || rc=$?
    local got=pass; [[ $rc -eq 0 ]] || got=fail
    if [[ "$got" != "$want" ]]; then
        echo "❌ $desc: expected $want, got $got (exit $rc)"; echo "$out" | sed 's/^/     /'
        failures=$((failures + 1)); return
    fi
    if [[ -n "$pattern" ]] && ! grep -qE "$pattern" <<< "$out"; then
        echo "❌ $desc: output does not match /$pattern/"; echo "$out" | sed 's/^/     /'
        failures=$((failures + 1)); return
    fi
    echo "✓ $desc"
}

# 1. Clean bundle passes, as a directory and as a tarball.
OK="$(new_bundle ok)"
cc_dylib "$OK/python/lib/_ok.so" 11.0
expect pass "11.0 bundle passes (dir)" "inspected 2 Mach-O" --macos-target 11.0 "$OK"
tar -czf "$WORK/ok.tar.gz" -C "$OK" .
expect pass "11.0 bundle passes (tar.gz)" "inspected 2 Mach-O" --macos-target 11.0 "$WORK/ok.tar.gz"

# 2. A dylib with a newer minos fails, and the offending file is named
#    (the Homebrew libcrypto bug: minos 15.0 inside an 11.0 bundle).
NEW="$(new_bundle newer)"
mkdir -p "$NEW/python/lib/lib-dynload"
cc_dylib "$NEW/python/lib/lib-dynload/libcrypto.3.dylib" 15.0
expect fail "minos 15.0 dylib is rejected (dir)" "libcrypto\.3\.dylib has minos 15\.0" --macos-target 11.0 "$NEW"
tar -czf "$WORK/newer.tar.gz" -C "$NEW" .
expect fail "minos 15.0 dylib is rejected (tar.gz)" "libcrypto\.3\.dylib has minos 15\.0" --macos-target 11.0 "$WORK/newer.tar.gz"
expect pass "same bundle passes with a 15.0 floor" "" --macos-target 15.0 "$NEW"
# A patch-level difference counts too.
cc_dylib "$NEW/python/lib/lib-dynload/libcrypto.3.dylib" 11.0.1
expect fail "minos 11.0.1 > 11.0 is rejected" "minos 11\.0\.1" --macos-target 11.0 "$NEW"

# 3. Old-style LC_VERSION_MIN_MACOSX (x86_64 with a pre-10.14 target) is read too.
OLD="$(new_bundle oldcmd)"
cc_exe "$OLD/python/bin/tool" 10.13 x86_64
otool -l "$OLD/python/bin/tool" | grep -q LC_VERSION_MIN_MACOSX \
    || { echo "❌ fixture: expected LC_VERSION_MIN_MACOSX in x86_64 10.13 binary"; exit 1; }
expect pass "LC_VERSION_MIN_MACOSX 10.13 passes an 11.0 floor" "" --macos-target 11.0 "$OLD"
expect fail "LC_VERSION_MIN_MACOSX 10.13 fails a 10.12 floor" "tool has minos 10\.13" --macos-target 10.12 "$OLD"

# 4. A Homebrew-linked library fails.
BREW="$(new_bundle brew)"
cc_dylib "$WORK/libfake.dylib" 11.0 -install_name /opt/homebrew/opt/openssl@3/lib/libfake.dylib
clang -isysroot "$SDK" -arch "$ARCH" -mmacosx-version-min=11.0 "$WORK/main.c" "$WORK/libfake.dylib" \
    -o "$BREW/python/bin/linked"
expect fail "Homebrew link is rejected" "links Homebrew library /opt/homebrew/opt/openssl@3/lib/libfake\.dylib" \
    --macos-target 11.0 "$BREW"

# 5. Nothing to check is an error, not a pass (the original build.sh bug:
#    it scanned out/ which only held the tarball).
mkdir -p "$WORK/empty"
echo 'not a binary' > "$WORK/empty/README"
expect fail "directory without Mach-O files is rejected" "no Mach-O files found" --macos-target 11.0 "$WORK/empty"
expect fail "missing path is rejected" "Not found" --macos-target 11.0 "$WORK/does-not-exist"

# 6. Usage errors.
expect fail "missing --macos-target is a usage error" "Usage" "$OK"

if [[ $failures -ne 0 ]]; then
    echo "🛑 $failures verify-bundle test(s) failed"
    exit 1
fi
echo "✅ verify-bundle.sh self-test passed"
