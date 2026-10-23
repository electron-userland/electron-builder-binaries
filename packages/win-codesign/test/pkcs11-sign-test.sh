#!/usr/bin/env bash
# PKCS#11 (HSM) signing smoke test for an osslsigncode bundle, using SoftHSM as the token.
#
# osslsigncode is invoked with exactly the argument shape electron-builder's Pkcs11SignManager
# uses (packages/app-builder-lib/src/codeSign/win/pkcs11SignManager.ts):
#   sign -in <file> -out <file> -pkcs11module <module> -key <pkcs11 URI> -certs <chain> -h sha256 -pass <PIN>
# (timestamping is left out so the test needs no network). With `-pkcs11module` and no
# `-pkcs11engine`, osslsigncode 2.11 first loads the libp11 "pkcs11prov" OpenSSL provider and
# falls back to the libp11 "pkcs11" engine, so libp11 must be reachable.
#
# Run: bash packages/win-codesign/test/pkcs11-sign-test.sh <bundle.zip | bundle dir>
# Env: SOFTHSM2_MODULE  path to libsofthsm2.so (auto-detected for Homebrew / Debian)
set -uo pipefail

PASS=0
FAIL=0
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

MODULE="${SOFTHSM2_MODULE:-}"
if [[ -z "$MODULE" ]]; then
    candidates=()
    if command -v brew >/dev/null 2>&1; then
        candidates+=("$(brew --prefix softhsm 2>/dev/null)/lib/softhsm/libsofthsm2.so")
    fi
    candidates+=(/usr/lib/softhsm/libsofthsm2.so /usr/lib/x86_64-linux-gnu/softhsm/libsofthsm2.so /usr/lib/aarch64-linux-gnu/softhsm/libsofthsm2.so)
    for c in "${candidates[@]}"; do
        [[ -f "$c" ]] && { MODULE="$c"; break; }
    done
fi
if [[ -z "$MODULE" || ! -f "$MODULE" ]]; then
    echo "❌ SoftHSM module not found; install softhsm (brew) / softhsm2 (apt) or set SOFTHSM2_MODULE" >&2
    exit 2
fi

echo "🧪 PKCS#11 signing with bundle at $BUNDLE"
echo "   module: $MODULE"

W="$TMPDIR_ROOT/work"
mkdir -p "$W/tokens"
export SOFTHSM2_CONF="$W/softhsm2.conf"
printf 'directories.tokendir = %s/tokens\nobjectstore.backend = file\nlog.level = ERROR\n' "$W" > "$SOFTHSM2_CONF"

cat > "$W/req.cnf" << 'EOF'
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = win-codesign pkcs11 smoke test
[ext]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
EOF

PIN=123456
LABEL=eb-test
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -sha256 -config "$W/req.cnf" \
    -keyout "$W/key.pem" -out "$W/cert.pem" >/dev/null 2>&1 || { fail "generate test certificate"; }
openssl pkcs8 -topk8 -nocrypt -in "$W/key.pem" -out "$W/key.p8" >/dev/null 2>&1 || { fail "convert key to PKCS#8"; }
if softhsm2-util --init-token --free --label "$LABEL" --pin "$PIN" --so-pin 12345678 >/dev/null \
    && softhsm2-util --import "$W/key.p8" --token "$LABEL" --label signkey --id 01 --pin "$PIN" >/dev/null; then
    pass "SoftHSM token initialised with the signing key"
else
    fail "SoftHSM token setup"
fi

printf 'Write-Output "hello"\r\n' > "$W/test.ps1"
KEY_URI="pkcs11:token=$LABEL;object=signkey;type=private"

code=0
"$OSSL" sign -in "$W/test.ps1" -out "$W/signed.ps1" \
    -pkcs11module "$MODULE" -key "$KEY_URI" -certs "$W/cert.pem" -h sha256 -pass "$PIN" \
    > "$W/sign.log" 2>&1 || code=$?
if [[ $code -eq 0 && -f "$W/signed.ps1" ]]; then
    pass "signs via -pkcs11module/-key (electron-builder argument shape)"
else
    fail "signing via -pkcs11module exited $code$([[ -f "$W/signed.ps1" ]] && echo ' (output written)')"
    sed 's/^/     /' "$W/sign.log" | tail -25
fi

if [[ -f "$W/signed.ps1" ]]; then
    if "$OSSL" verify -in "$W/signed.ps1" -CAfile "$W/cert.pem" > "$W/verify.log" 2>&1; then
        pass "verifies the PKCS#11-signed file"
    else
        fail "verification of the PKCS#11-signed file failed"; sed 's/^/     /' "$W/verify.log" | tail -10
    fi
fi

echo ""
echo "═══════════════════════════════════════"
echo "Results: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════"
[ "$FAIL" -eq 0 ]
