#!/usr/bin/env bash
# Smoke tests for the macOS osslsigncode bundle produced by build-mac.sh.
#   - the binary and its bundled OpenSSL / pkcs11prov dylibs link only against macOS system
#     libraries and each other (no Homebrew OpenSSL), embed no Homebrew paths and target
#     macOS <= $EXPECTED_MIN_MACOS (default 11.0)
#   - every binary ships its license in LICENSES/ (scripts/verify-licenses.sh), including osslsigncode's full GPLv3 text
#   - it reports the bundled OpenSSL version
#   - it can sign and verify with a legacy (RC2/3DES) PKCS#12 file, which needs the
#     legacy provider compiled into libcrypto, and with PEM key + certificate
#
# Run: bash packages/win-codesign/test/build-mac-test.sh <win-codesign-darwin-*.zip | extracted bundle dir>
# The linkage check only runs on macOS; the license and signing checks run anywhere.
# shellcheck disable=SC2001 # sed indents every line of multi-line output; ${var//...} cannot anchor at line starts
set -uo pipefail

PASS=0
FAIL=0
ASSETS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../assets" && pwd)"
EXPECTED_OPENSSL="${EXPECTED_OPENSSL:-OpenSSL 3.5.}"
EXPECTED_MIN_MACOS="${EXPECTED_MIN_MACOS:-11.0}"

pass() { echo "  ✅ $1"; PASS=$(( PASS + 1 )); }
fail() { echo "  ❌ $1"; FAIL=$(( FAIL + 1 )); }

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <bundle.zip | bundle dir>" >&2
    exit 2
fi

TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

if [[ -d "$1" ]]; then
    BUNDLE="$(cd "$1" && pwd)"
else
    BUNDLE="$TMPDIR_ROOT/bundle"
    mkdir -p "$BUNDLE"
    unzip -q "$1" -d "$BUNDLE"
fi
OSSL="$BUNDLE/osslsigncode"
BIN="$BUNDLE/bin/osslsigncode"

echo "🧪 Testing bundle at $BUNDLE"

# ── Linkage ───────────────────────────────────────────────────────────────────
if [[ "$(uname -s)" == "Darwin" ]]; then
    for f in libcrypto.3.dylib libssl.3.dylib ossl-modules/pkcs11prov.dylib; do
        if [[ -f "$BUNDLE/lib/$f" ]]; then
            pass "bundle ships lib/$f"
        else
            fail "bundle is missing lib/$f"
        fi
    done
    MACHO=("$BIN")
    while IFS= read -r -d '' f; do MACHO+=("$f"); done < <(find "$BUNDLE/lib" -type f -name '*.dylib' -print0)
    if bash "$ASSETS_DIR/verify-macos-linkage.sh" --lib-dir "$BUNDLE/lib" --macos-target "$EXPECTED_MIN_MACOS" "${MACHO[@]}"; then
        pass "binary and bundled dylibs link only macOS system libraries and each other, embed no Homebrew paths, target macOS <= $EXPECTED_MIN_MACOS"
    else
        fail "bundle links libraries outside macOS and the bundle, embeds Homebrew paths, or targets macOS > $EXPECTED_MIN_MACOS"
    fi
    if /usr/bin/codesign -v --strict "${MACHO[@]}" 2>/dev/null; then
        pass "binary and bundled dylibs carry valid (ad-hoc) signatures"
    else
        fail "invalid code signature in bundle"
    fi
else
    echo "  ⏭  linkage check skipped (not macOS)"
fi

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
if [[ -f "$ASSETS_DIR/../../../scripts/verify-licenses.sh" ]]; then
    if bash "$ASSETS_DIR/verify-bundle-licenses.sh" "$BUNDLE"; then
        pass "every binary ships its license (scripts/verify-licenses.sh)"
    else
        fail "binaries without license files (scripts/verify-licenses.sh)"
    fi
else
    fail "license guard scripts/verify-licenses.sh not found"
fi

# ── Version ───────────────────────────────────────────────────────────────────
VERSION_OUT="$("$OSSL" --version 2>&1 || true)"
echo "$VERSION_OUT" | sed 's/^/     /'
if grep -q "Library: $EXPECTED_OPENSSL" <<< "$VERSION_OUT"; then
    pass "reports bundled $EXPECTED_OPENSSL library"
else
    fail "expected 'Library: $EXPECTED_OPENSSL' in --version output"
fi

# ── Sign / verify ─────────────────────────────────────────────────────────────
W="$TMPDIR_ROOT/work"
mkdir -p "$W"
cat > "$W/req.cnf" << 'EOF'
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = win-codesign smoke test
[ext]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
EOF

if ! openssl req -x509 -newkey rsa:2048 -nodes -days 2 -sha256 \
        -config "$W/req.cnf" -keyout "$W/key.pem" -out "$W/cert.pem" >/dev/null 2>&1; then
    fail "could not generate a test certificate with $(command -v openssl)"
else
    # Legacy PBE (RC2-40 / 3DES) is what LibreSSL (/usr/bin/openssl on macOS) writes by
    # default; OpenSSL 3 needs -legacy to produce the same.
    P12_ARGS=()
    if openssl pkcs12 -help 2>&1 | grep -q -- '-legacy'; then
        P12_ARGS+=(-legacy)
    fi
    # ${arr[@]+...} form: macOS bash 3.2 treats an empty array as unbound under `set -u`.
    openssl pkcs12 -export ${P12_ARGS[@]+"${P12_ARGS[@]}"} -inkey "$W/key.pem" -in "$W/cert.pem" \
        -out "$W/legacy.p12" -passout pass:smoke >/dev/null 2>&1

    printf 'Write-Output "hello"\r\n' > "$W/test.ps1"

    if "$OSSL" sign -pkcs12 "$W/legacy.p12" -pass smoke -h sha256 -n "smoke" \
            -in "$W/test.ps1" -out "$W/signed-p12.ps1" > "$W/sign-p12.log" 2>&1; then
        pass "signs with a legacy-encrypted PKCS#12 (built-in legacy provider)"
    else
        fail "signing with legacy PKCS#12 failed"; sed 's/^/     /' "$W/sign-p12.log"
    fi

    if "$OSSL" sign -certs "$W/cert.pem" -key "$W/key.pem" -h sha256 \
            -in "$W/test.ps1" -out "$W/signed-pem.ps1" > "$W/sign-pem.log" 2>&1; then
        pass "signs with PEM key + certificate"
    else
        fail "signing with PEM key + certificate failed"; sed 's/^/     /' "$W/sign-pem.log"
    fi

    for f in signed-p12 signed-pem; do
        [[ -f "$W/$f.ps1" ]] || continue
        if "$OSSL" verify -in "$W/$f.ps1" -CAfile "$W/cert.pem" > "$W/verify-$f.log" 2>&1; then
            pass "verifies $f.ps1"
        else
            fail "verification of $f.ps1 failed"; sed 's/^/     /' "$W/verify-$f.log"
        fi
    done
fi

# ── Results ───────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════"
echo "Results: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════"
[ "$FAIL" -eq 0 ]
