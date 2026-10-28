#!/usr/bin/env bash
# Smoke tests for the Linux osslsigncode bundle produced by build-linux.sh.
#   - the bundle ships its OpenSSL libraries and pkcs11prov in lib/, and every binary's license in LICENSES/
#     (scripts/verify-licenses.sh layout, including osslsigncode's full GPLv3 text)
#   - the binary and bundled libraries need only base-system libraries (glibc, libz) or each
#     other, use $ORIGIN-relative RUNPATHs and need glibc <= $EXPECTED_MAX_GLIBC (default 2.31)
#   - bin/osslsigncode resolves the bundled libcrypto through its RUNPATH alone (no launcher)
#   - version, legacy PKCS#12 and PEM sign/verify checks shared with the macOS bundle
#     (build-mac-test.sh, whose own linkage section only runs on macOS)
#
# Meant to run on a distro without OpenSSL 1.1 (see build-linux-docker-test.sh).
# Run: bash packages/win-codesign/test/build-linux-test.sh <win-codesign-linux-*.zip | extracted bundle dir>
# shellcheck disable=SC2001 # sed indents every line of multi-line output; ${var//...} cannot anchor at line starts
set -uo pipefail

PASS=0
FAIL=0
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="$(cd "$TEST_DIR/../assets" && pwd)"
EXPECTED_OPENSSL="${EXPECTED_OPENSSL:-OpenSSL 3.5.}"
EXPECTED_MAX_GLIBC="${EXPECTED_MAX_GLIBC:-2.31}"

pass() { echo "  ✅ $1"; PASS=$(( PASS + 1 )); }
fail() { echo "  ❌ $1"; FAIL=$(( FAIL + 1 )); }

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <bundle.zip | bundle dir>" >&2
    exit 2
fi

TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

if [[ -d "$1" ]]; then
    BUNDLE="$(cd "$1" && pwd -P)"
else
    BUNDLE="$TMPDIR_ROOT/bundle"
    mkdir -p "$BUNDLE"
    unzip -q "$1" -d "$BUNDLE"
    BUNDLE="$(cd "$BUNDLE" && pwd -P)"
fi
BIN="$BUNDLE/bin/osslsigncode"

echo "🧪 Testing Linux bundle at $BUNDLE"

# ── Contents ──────────────────────────────────────────────────────────────────
for f in libcrypto.so.3 libssl.so.3 ossl-modules/pkcs11prov.so; do
    if [[ -f "$BUNDLE/lib/$f" ]]; then
        pass "bundle ships lib/$f"
    else
        fail "bundle is missing lib/$f"
    fi
done

# ── Licenses ──────────────────────────────────────────────────────────────────
for f in LICENSES/MANIFEST.tsv LICENSES/SOURCES.tsv LICENSES/osslsigncode/LICENSE.txt LICENSES/osslsigncode/COPYING.txt \
    LICENSES/openssl/LICENSE.txt LICENSES/libp11/COPYING; do
    if [[ -s "$BUNDLE/$f" ]]; then
        pass "bundle ships $f"
    else
        fail "bundle is missing $f"
    fi
done
if grep -q "GNU GENERAL PUBLIC LICENSE" "$BUNDLE/LICENSES/osslsigncode/COPYING.txt" 2>/dev/null \
    && grep -q "Version 3" "$BUNDLE/LICENSES/osslsigncode/COPYING.txt"; then
    pass "LICENSES/osslsigncode/COPYING.txt is the full GPLv3 text"
else
    fail "LICENSES/osslsigncode/COPYING.txt is not the GPLv3 text"
fi
# scripts/verify-licenses.sh lives at the repository root, which is not mounted in the Docker test.
if [[ -f "$ASSETS_DIR/../../../scripts/verify-licenses.sh" ]]; then
    if bash "$ASSETS_DIR/verify-bundle-licenses.sh" "$BUNDLE"; then
        pass "every binary ships its license (scripts/verify-licenses.sh)"
    else
        fail "binaries without license files (scripts/verify-licenses.sh)"
    fi
else
    echo "  ⏭  license guard not available here (build-linux-docker-test.sh runs it on the zip)"
fi

# ── Linkage ───────────────────────────────────────────────────────────────────
ELF=("$BIN")
while IFS= read -r -d '' f; do ELF+=("$f"); done < <(find "$BUNDLE/lib" -type f -name '*.so*' -print0)
if bash "$ASSETS_DIR/verify-linux-linkage.sh" --lib-dir "$BUNDLE/lib" --max-glibc "$EXPECTED_MAX_GLIBC" "${ELF[@]}"; then
    pass "binary and bundled libraries need only base-system libraries and each other, glibc <= $EXPECTED_MAX_GLIBC"
else
    fail "bundle needs libraries outside the base system and the bundle, or a newer glibc"
fi

# Without the launcher's LD_LIBRARY_PATH, the RUNPATH alone must find the bundled libcrypto.
LDD_OUT="$(env -u LD_LIBRARY_PATH ldd "$BIN" 2>&1 || true)"
echo "$LDD_OUT" | sed 's/^/     /'
LIBCRYPTO_PATH="$(awk '$1 == "libcrypto.so.3" && $2 == "=>" {print $3}' <<< "$LDD_OUT")"
if grep -q "not found" <<< "$LDD_OUT"; then
    fail "ldd reports unresolved libraries"
elif [[ -n "$LIBCRYPTO_PATH" && "$(readlink -f "$LIBCRYPTO_PATH")" == "$BUNDLE/lib/libcrypto.so.3" ]]; then
    pass "RUNPATH resolves libcrypto.so.3 inside the bundle"
else
    fail "libcrypto.so.3 does not resolve to the bundled copy"
fi

DIRECT_OUT="$(env -u LD_LIBRARY_PATH -u OPENSSL_MODULES "$BIN" --version 2>&1 || true)"
if grep -q "Library: $EXPECTED_OPENSSL" <<< "$DIRECT_OUT"; then
    pass "bin/osslsigncode runs without the launcher and reports $EXPECTED_OPENSSL"
else
    fail "bin/osslsigncode without the launcher: $(head -n1 <<< "$DIRECT_OUT")"
fi

# ── Version + sign / verify (shared with the macOS bundle test) ───────────────
# The license guard ran above when the repository is available; otherwise build-linux-docker-test.sh runs it on the zip.
if EXPECTED_OPENSSL="$EXPECTED_OPENSSL" LICENSE_GUARD_RUN_BY_CALLER=1 bash "$TEST_DIR/build-mac-test.sh" "$BUNDLE"; then
    pass "version, legacy PKCS#12 and PEM sign/verify checks"
else
    fail "version, legacy PKCS#12 or PEM sign/verify checks (see above)"
fi

echo ""
echo "═══════════════════════════════════════"
echo "Results: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════"
[ "$FAIL" -eq 0 ]
