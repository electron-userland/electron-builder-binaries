#!/usr/bin/env bash
# Self-test for packages/fpm/assets/collect-licenses.sh (and verify-archive-licenses.sh): builds tiny Linux and macOS
# fpm bundles whose "binaries" are just magic bytes, with stub dpkg/dpkg-query/brew commands standing in for the build
# image and Homebrew, then checks the collected LICENSES/ passes scripts/verify-licenses.sh, and that a library
# without a known license, a missing Ruby license file, or an ambiguous package fails.
# The license "texts" here are placeholders for the test only. Portable bash: Linux and macOS (bash 3.2).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECT="$HERE/../assets/collect-licenses.sh"
VERIFY_ARCHIVES="$HERE/../assets/verify-archive-licenses.sh"
export VERIFY_LICENSES="$HERE/../../../scripts/verify-licenses.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/collect-licenses-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
RUBY_DIR=ruby-3.4.12-portable

elf()     { mkdir -p "$(dirname "$1")"; printf '\177ELF\002\001\001\000padding' > "$1"; }
macho()   { mkdir -p "$(dirname "$1")"; printf '\317\372\355\376\007\000\000\001padding' > "$1"; }
fixture() { mkdir -p "$(dirname "$1")"; printf 'test fixture: %s\n' "${2:-license text}" > "$1"; }

# --- Stub commands ---
STUBS="$WORK/stubs"
mkdir -p "$STUBS"
# dpkg -S '*/<name>' answers from $DPKG_TABLE ("<name><TAB><dpkg -S output line>")
cat > "$STUBS/dpkg" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    --print-architecture) echo amd64 ;;
    -S)
        name="${2#\*/}"
        out=$(awk -F'\t' -v n="$name" '$1 == n {print $2}' "$DPKG_TABLE")
        [ -n "$out" ] || { echo "dpkg-query: no path found matching pattern $2" >&2; exit 1; }
        printf '%s\n' "$out"
        ;;
    *) exit 2 ;;
esac
EOF
cat > "$STUBS/dpkg-query" <<'EOF'
#!/usr/bin/env bash
case "$2" in
    *source:Package*) printf '%s-src 1.0-1' "$3" ;;
    *) printf '1.0-1' ;;
esac
EOF
cat > "$STUBS/brew" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    --prefix) echo "$BREW_ROOT/opt/$2" ;;
    list) echo "$3 1.0" ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$STUBS"/*

# --- Bundles ---
# base_bundle <dir>: the parts both OSes share
base_bundle() {
    local d="$1"
    rm -rf "$d"
    fixture "$d/$RUBY_DIR/gems/gems/fpm-1.18.0/LICENSE" "fpm"
    printf '#!/usr/bin/env bash\n' > "$d/fpm"
    for f in COPYING BSDL LEGAL; do fixture "$d/LICENSES/ruby/$f" "ruby $f"; done
}

# linux_bundle <dir>: Debian doc tree in $d.root, static OpenSSL in $d.openssl
linux_bundle() {
    local d="$1" r="$1.root"
    base_bundle "$d"
    rm -rf "$r" "$d.openssl"
    elf "$d/$RUBY_DIR/bin/ruby"
    for lib in libz.so.1 libyaml-0.so.2 libffi.so.6 libgmp.so.10; do elf "$d/$RUBY_DIR/lib/$lib"; done
    elf "$d/$RUBY_DIR/lib/ruby/gems/3.4.0/extensions/x86_64-linux/3.4.0-static/racc-1.8.1/racc/cparse.so"
    fixture "$d/$RUBY_DIR/lib/ruby/gems/3.4.0/gems/racc-1.8.1/BSDL" "racc"
    fixture "$d.openssl/LICENSE.txt" "openssl"
    for pkg in zlib1g libyaml-0-2 libffi6 libgmp10; do fixture "$r/doc/$pkg/copyright" "$pkg copyright"; done
    printf 'see `/usr/share/common-licenses/{MPL-1.1,GPL-2}'"'"'.\nand /usr/share/common-licenses/GPL.\n' >> "$r/doc/libffi6/copyright"
    printf 'The GNU Lesser General Public License v3 text is contained in /usr/share/common-licenses/LGPL-3.\n' >> "$r/doc/libgmp10/copyright"
    for l in MPL-1.1 GPL-2 GPL LGPL-3; do fixture "$r/common-licenses/$l" "$l"; done
    {
        printf 'libz.so.1\tzlib1g:amd64: /lib/x86_64-linux-gnu/libz.so.1\n'
        printf 'libyaml-0.so.2\tlibyaml-0-2:amd64: /usr/lib/x86_64-linux-gnu/libyaml-0.so.2\n'
        # another architecture's package is ignored
        printf 'libffi.so.6\tlibffi6:amd64: /usr/lib/x86_64-linux-gnu/libffi.so.6\nlibffi.so.6\tlib32ffi6:i386: /usr/lib32/libffi.so.6\n'
        printf 'libgmp.so.10\tlibgmp10:amd64: /usr/lib/x86_64-linux-gnu/libgmp.so.10\n'
    } > "$r/dpkg-table"
}

# mac_bundle <dir>: Homebrew kegs in $d.brew
mac_bundle() {
    local d="$1" b="$1.brew" f
    base_bundle "$d"
    rm -rf "$b"
    macho "$d/$RUBY_DIR/bin/ruby"
    for f in libssl.3.dylib libcrypto.3.dylib libz.1.3.2.dylib libyaml-0.2.dylib libgmp.10.dylib libgmpxx.4.dylib liblzma.5.dylib; do
        macho "$d/$RUBY_DIR/lib/$f"
    done
    ln -s libz.1.3.2.dylib "$d/$RUBY_DIR/lib/libz.dylib"
    fixture "$b/opt/openssl@3/LICENSE.txt" "openssl"
    fixture "$b/opt/zlib/README" "zlib README"
    fixture "$b/opt/libyaml/License" "libyaml"
    fixture "$b/opt/gmp/COPYING.LESSERv3" "gmp"
    fixture "$b/opt/gmp/COPYINGv2" "gmp"
    fixture "$b/opt/xz/COPYING" "xz"
    fixture "$b/opt/xz/AUTHORS" "not a license"
}

failures=0
OUT=""
fail() {
    echo "❌ $1"
    printf '%s\n' "$OUT" | sed 's/^/     /'
    failures=$((failures + 1))
}

# collect <os> <bundle>: runs collect-licenses.sh then verify-licenses.sh; sets OUT and RC (0 both pass, 1 collect
# failed, 2 guard failed)
collect() {
    local os="$1" d="$2"
    RC=0
    OUT="$(PATH="$STUBS:$PATH" LICENSE_OS="$os" DPKG_TABLE="$d.root/dpkg-table" BREW_ROOT="$d.brew" \
        DEBIAN_DOC_DIR="$d.root/doc" COMMON_LICENSES_DIR="$d.root/common-licenses" OPENSSL_PREFIX="$d.openssl" \
        bash "$COLLECT" "$d" "$RUBY_DIR" 2>&1)" || RC=1
    if [ "$RC" -eq 0 ]; then
        OUT="$OUT"$'\n'"$(bash "$VERIFY_LICENSES" "$d" 2>&1)" || RC=2
    fi
}

# expect_rc <description> <want rc> [grep -E pattern the output must match...]
expect_rc() {
    local desc="$1" want="$2" pattern
    shift 2
    if [ "$RC" -ne "$want" ]; then
        fail "$desc: expected result $want, got $RC"
        return 0
    fi
    for pattern in "$@"; do
        if ! printf '%s\n' "$OUT" | grep -Eq -- "$pattern"; then
            fail "$desc: output does not match /$pattern/"
            return 0
        fi
    done
    echo "✓ $desc"
}

# has_line <file> <line>
has_line() { grep -qxF -- "$2" "$1"; }
TAB=$(printf '\t')

# --- Linux ---
D="$WORK/linux"
linux_bundle "$D"
collect Linux "$D"
expect_rc "linux: licenses collected and the guard passes" 0 "All 6 binaries have license files"
M="$D/LICENSES/MANIFEST.tsv"
for line in "$RUBY_DIR/bin/ruby${TAB}ruby" "$RUBY_DIR/bin/ruby${TAB}openssl" "$RUBY_DIR/lib/libz.so.1${TAB}zlib" \
    "$RUBY_DIR/lib/libyaml-0.so.2${TAB}libyaml" "$RUBY_DIR/lib/libffi.so.6${TAB}libffi" "$RUBY_DIR/lib/libgmp.so.10${TAB}gmp" \
    "$RUBY_DIR/lib/ruby/gems/3.4.0/extensions/x86_64-linux/3.4.0-static/racc-1.8.1/racc/cparse.so${TAB}racc"; do
    has_line "$M" "$line" || { OUT=$(cat "$M"); fail "linux: MANIFEST.tsv lacks: $line"; }
done
for f in fpm/LICENSE openssl/LICENSE.txt zlib/copyright zlib/SOURCE.txt libffi/copyright libffi/common-licenses/MPL-1.1 \
    libffi/common-licenses/GPL-2 libffi/common-licenses/GPL gmp/common-licenses/LGPL-3 racc/BSDL ruby/LEGAL; do
    [ -s "$D/LICENSES/$f" ] || { OUT=$(cd "$D/LICENSES" && find . -type f); fail "linux: LICENSES/$f missing"; }
done
grep -q 'libffi6 1.0-1' "$D/LICENSES/libffi/SOURCE.txt" || { OUT=$(cat "$D/LICENSES/libffi/SOURCE.txt"); fail "linux: SOURCE.txt names the package"; }

linux_bundle "$D"
rm "$D/LICENSES/ruby/LEGAL"
collect Linux "$D"
expect_rc "linux: a missing Ruby LEGAL fails" 1 "LICENSES/ruby/LEGAL is missing"

linux_bundle "$D"
rm "$D/$RUBY_DIR/gems/gems/fpm-1.18.0/LICENSE"
collect Linux "$D"
expect_rc "linux: a missing fpm gem LICENSE fails" 1 "fpm gem LICENSE"

linux_bundle "$D"
printf 'libgmp.so.10\tlibgmp10-alt:amd64: /usr/lib/alt/libgmp.so.10\n' >> "$D.root/dpkg-table"
collect Linux "$D"
expect_rc "linux: a library shipped by two packages fails" 1 "several Debian packages ship it"

linux_bundle "$D"
elf "$D/$RUBY_DIR/lib/libreadline.so.7"
collect Linux "$D"
expect_rc "linux: a library without a license mapping fails the guard" 2 "libreadline.so.7: elf binary not listed"

linux_bundle "$D"
elf "$D/$RUBY_DIR/lib/libz.so.1.2.11"
collect Linux "$D"
expect_rc "linux: a library no package ships fails" 1 "libz.so.1.2.11: no installed Debian package"

linux_bundle "$D"
rm "$D.root/doc/libyaml-0-2/copyright"
collect Linux "$D"
expect_rc "linux: a missing Debian copyright file fails" 1 "libyaml-0-2/copyright is missing"

# --- macOS ---
D="$WORK/mac"
mac_bundle "$D"
collect Darwin "$D"
expect_rc "mac: licenses collected and the guard passes" 0 "All 8 binaries have license files"
M="$D/LICENSES/MANIFEST.tsv"
for line in "$RUBY_DIR/bin/ruby${TAB}ruby" "$RUBY_DIR/lib/libssl.3.dylib${TAB}openssl" "$RUBY_DIR/lib/libcrypto.3.dylib${TAB}openssl" \
    "$RUBY_DIR/lib/libz.1.3.2.dylib${TAB}zlib" "$RUBY_DIR/lib/libgmpxx.4.dylib${TAB}gmp" "$RUBY_DIR/lib/liblzma.5.dylib${TAB}xz"; do
    has_line "$M" "$line" || { OUT=$(cat "$M"); fail "mac: MANIFEST.tsv lacks: $line"; }
done
if has_line "$M" "$RUBY_DIR/bin/ruby${TAB}openssl"; then OUT=$(cat "$M"); fail "mac: bin/ruby links OpenSSL dynamically"; fi
for f in openssl/LICENSE.txt zlib/README libyaml/License gmp/COPYING.LESSERv3 gmp/COPYINGv2 xz/COPYING xz/SOURCE.txt; do
    [ -s "$D/LICENSES/$f" ] || { OUT=$(cd "$D/LICENSES" && find . -type f); fail "mac: LICENSES/$f missing"; }
done
[ ! -e "$D/LICENSES/xz/AUTHORS" ] || { OUT=""; fail "mac: copied a file that is not a license"; }

mac_bundle "$D"
macho "$D/$RUBY_DIR/lib/libreadline.8.3.dylib"
collect Darwin "$D"
expect_rc "mac: readline (no license mapping) fails the guard" 2 "libreadline.8.3.dylib: macho binary not listed"

mac_bundle "$D"
rm "$D.brew/opt/gmp/"COPYING*
collect Darwin "$D"
expect_rc "mac: a keg without license files fails" 1 "no license file found in the Homebrew keg"

mac_bundle "$D"
macho "$D/tool"
collect Darwin "$D"
expect_rc "mac: an unknown binary fails the guard" 2 "tool: macho binary not listed"

# --- verify-archive-licenses.sh ---
SEVEN_ZIP="$(command -v 7zz || command -v 7za || command -v 7z || true)"
if [ -n "$SEVEN_ZIP" ]; then
    D="$WORK/linux"
    linux_bundle "$D"
    collect Linux "$D"
    (cd "$D" && "$SEVEN_ZIP" a -bd "$WORK/good.7z" . >/dev/null)
    rm "$D/LICENSES/racc/BSDL"
    (cd "$D" && "$SEVEN_ZIP" a -bd "$WORK/bad.7z" . >/dev/null)
    RC=0; OUT="$(bash "$VERIFY_ARCHIVES" "$WORK/good.7z" 2>&1)" || RC=1
    expect_rc "archives: a complete archive passes" 0 "All 6 binaries"
    RC=0; OUT="$(bash "$VERIFY_ARCHIVES" "$WORK/good.7z" "$WORK/bad.7z" 2>&1)" || RC=1
    expect_rc "archives: an archive missing a license fails" 1 "LICENSES/racc/: has no non-empty license file"
else
    echo "ℹ️  7-Zip not found: skipping the verify-archive-licenses.sh cases"
fi

echo ""
if [ "$failures" -gt 0 ]; then
    echo "❌ $failures collect-licenses test(s) failed"
    exit 1
fi
echo "✓ All collect-licenses tests passed"
