#!/usr/bin/env bash
set -euo pipefail

### ================================
### ARGS
### ================================
BUNDLE_DIR=""
MAX_MINOS="15.0"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bundle-dir) BUNDLE_DIR="$2"; shift 2 ;;
        --max-minos)  MAX_MINOS="$2";  shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

if [[ -z "$BUNDLE_DIR" ]]; then
    echo "Usage: $0 --bundle-dir <path-to-extracted-bundle> [--max-minos 15.0]"
    exit 1
fi

if [[ ! -d "$BUNDLE_DIR/bin" ]]; then
    echo "❌ No bin/ directory found in $BUNDLE_DIR"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(cd "$BUNDLE_DIR" && pwd -P)"
BIN="$BUNDLE_DIR/bin"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# No DYLD_* fallbacks and no Homebrew on PATH: the bundle must work on its own,
# the way electron-builder runs it (bin/ prepended to PATH for fpm; lzip called directly).
clean_env() {
    env -i HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" PATH="$BIN:/usr/bin:/bin:/usr/sbin:/sbin" "$@"
}

### ================================
### HELPERS
### ================================
pass=0
fail=0

ok() {
    echo "  ✅ $1"
    pass=$((pass + 1))
}

fail_test() {
    echo "  ❌ $1"
    fail=$((fail + 1))
}

run_test() {
    local label="$1"; shift
    local out
    if out="$("$@" 2>&1)"; then
        ok "$label"
    else
        fail_test "$label"
        echo "$out" | sed 's/^/      /'
    fi
}

echo "🧪 Testing linux-tools-mac bundle at: $BUNDLE_DIR"
echo ""

### ================================
### STATIC: allowlist, linkage, minos, signatures
### ================================
echo "── verify-bundle ──"
run_test "verify-bundle.sh (self-contained, minos <= $MAX_MINOS)" \
    bash "$SCRIPT_DIR/verify-bundle.sh" --bundle-dir "$BUNDLE_DIR" --max-minos "$MAX_MINOS"

### ================================
### RUNTIME: every loaded image comes from the bundle or the OS
### ================================
echo ""
echo "── runtime linkage (DYLD_PRINT_LIBRARIES) ──"
# Print every image dyld loads for `<bundle>/bin/<tool> --version` that is not
# from the bundle or the OS. Lines look like "dyld[123]: <UUID> /path".
# Returns 2 if dyld printed no image list at all (so silence never passes).
foreign_images() {
    local bundle="$1" tool="$2" log="$WORK/dyld-$2.log"
    bundle="$(cd "$bundle" && pwd -P)"
    env -i HOME="$HOME" PATH="$bundle/bin:/usr/bin:/bin" DYLD_PRINT_LIBRARIES=1 \
        "$bundle/bin/$tool" --version > /dev/null 2> "$log" || true
    grep -q '/usr/lib/libSystem' "$log" || { sed 's/^/      /' "$log" >&2; return 2; }
    sed -nE 's/^dyld\[[0-9]+\]: (<[^>]*> )?//p' "$log" \
        | grep -v -e "^$bundle/" -e '^/usr/lib/' -e '^/System/' || true
}

for tool in gtar lzip ar; do
    if ! bad="$(foreign_images "$BUNDLE_DIR" "$tool")"; then
        fail_test "$tool: DYLD_PRINT_LIBRARIES produced no image list"
    elif [[ -n "$bad" ]]; then
        fail_test "$tool loads images outside the bundle/OS:"
        echo "$bad" | sed 's/^/      /'
    else
        ok "$tool loads only bundle + OS images ($(grep -c "$BUNDLE_DIR/" "$WORK/dyld-$tool.log") from bundle)"
    fi
done

### ================================
### VERSIONS
### ================================
echo ""
echo "── versions ──"
for tool in gtar lzip ar; do
    if v="$(clean_env "$BIN/$tool" --version 2>&1 | head -n 1)"; then
        ok "$tool: $v"
    else
        fail_test "$tool --version"
    fi
done

### ================================
### FUNCTIONAL: what fpm and electron-builder actually run
### ================================
echo ""
echo "── fpm tar_cmd / ar_cmd probes ──"
cd "$WORK"
: > empty

# Helpers run inside clean_env (env -i drops exported functions, so source them)
cat > "$WORK/helpers.sh" <<'HELPERS'
set -e
# fpm FPM::Util#tar_cmd: first of tar/gtar/gnutar that accepts both
# --sort=name and --mtime=@0 (deterministic archives)
fpm_tar_cmd() {
    local tar opt score best="tar" bestscore=0
    for tar in tar gtar gnutar; do
        score=0
        for opt in --sort=name --mtime=@0; do
            "$tar" "$opt" -cf probe.tar empty > /dev/null 2>&1 && score=$((score + 1))
        done
        if (( score > bestscore )); then best="$tar"; bestscore="$score"; fi
        (( score == 2 )) && break
    done
    echo "$best:$bestscore"
}

# What fpm -t deb does: control + data tarballs via tar_cmd, then `ar -qc`.
# $2 is the compression flag ("-z" for gz, "" for none).
make_deb() {
    local out="$1" z="${2:-}" ext=""
    [[ -n "$z" ]] && ext=".gz"
    rm -rf staging control build && mkdir -p staging/opt/app control build
    printf 'hello\n' > staging/opt/app/hello.txt
    printf 'Package: t\nVersion: 1\nArchitecture: amd64\n' > control/control
    printf '2.0\n' > build/debian-binary
    gtar -C control $z -cf "build/control.tar$ext" --owner=0 --group=0 --numeric-owner . --sort=name --mtime=@0
    gtar -C staging $z -cf "build/data.tar$ext" --owner=0 --group=0 --numeric-owner . --sort=name --mtime=@0
    (cd build && rm -f "$out" && ar -qc "$out" debian-binary "control.tar$ext" "data.tar$ext")
}
HELPERS

probe="$(clean_env bash -c 'cd "$1" && . ./helpers.sh && fpm_tar_cmd' _ "$WORK")"
if [[ "$probe" == "gtar:2" && "$(clean_env bash -c 'command -v gtar')" == "$BIN/gtar" ]]; then
    ok "fpm tar_cmd selects bundled gtar (deterministic)"
else
    fail_test "fpm tar_cmd probe returned '$probe'"
fi

# fpm FPM::Util#ar_cmd: `ar -qc` must produce uid 0 / epoch timestamps
run_test "fpm ar_cmd probe: bundled ar -qc is deterministic" clean_env bash -c '
    cd "$1" && rm -f probe.a &&
    [[ "$(command -v ar)" == "$2/ar" ]] &&
    ar -qc probe.a empty &&
    env TZ=UTC LANG=C LC_TIME=C ar -tv probe.a | grep -q "0/0.*1970"' _ "$WORK" "$BIN"

echo ""
echo "── deb assembly (fpm -t deb, gz) ──"
run_test "build .deb with bundled gtar + ar" clean_env bash -c 'cd "$1" && . ./helpers.sh && make_deb "$1/a.deb" -z' _ "$WORK"
run_test ".deb member order is debian-binary, control, data" clean_env bash -c '
    [[ "$(ar t "$1/a.deb" | tr "\n" " ")" == "debian-binary control.tar.gz data.tar.gz " ]]' _ "$WORK"
run_test ".deb data.tar.gz extracts" clean_env bash -c '
    ar p "$1/a.deb" data.tar.gz | gtar -tzf - | grep -q "./opt/app/hello.txt"' _ "$WORK"
run_test ".deb (uncompressed) is byte-for-byte reproducible" clean_env bash -c '
    cd "$1" && . ./helpers.sh && make_deb "$1/r1.deb" && sleep 1 && make_deb "$1/r2.deb" && cmp -s r1.deb r2.deb' _ "$WORK"

echo ""
echo "── sh/pacman payload (gtar --owner/--group/--numeric-owner) ──"
run_test "gtar payload tar" clean_env bash -c '
    cd "$1" && gtar -C staging -cf payload.tar --owner=0 --group=0 --numeric-owner . &&
    gtar -tvf payload.tar | grep -q "0/0"' _ "$WORK"

echo ""
echo "── tar.lz (electron-builder archive target) ──"
run_test "lzip -9 --keep, test and round-trip" clean_env bash -c '
    cd "$1" && rm -f payload.tar.lz &&
    "$2/lzip" -9 --keep payload.tar && [[ -f payload.tar && -f payload.tar.lz ]] &&
    "$2/lzip" -t payload.tar.lz &&
    "$2/lzip" -dc payload.tar.lz | cmp -s - payload.tar' _ "$WORK" "$BIN"

### ================================
### VERIFIER SELF-TEST: prove the guard rejects broken bundles
### ================================
echo ""
echo "── verify-bundle self-test (must reject) ──"
expect_reject() {
    local label="$1" dir="$2"
    if bash "$SCRIPT_DIR/verify-bundle.sh" --bundle-dir "$dir" --max-minos "$MAX_MINOS" > "$WORK/reject.log" 2>&1; then
        fail_test "verify-bundle accepted: $label"
    else
        ok "verify-bundle rejects: $label ($(grep -m1 '❌' "$WORK/reject.log" | sed 's/^ *//'))"
    fi
}
fresh_copy() {
    rm -rf "$WORK/copy" && cp -R "$BUNDLE_DIR" "$WORK/copy" && echo "$WORK/copy"
}

# 1. a load path pointing back at Homebrew
c="$(fresh_copy)"
victim=""; victim_dep=""
for f in "$c"/bin/* "$c"/lib/*; do
    [[ -f "$f" && ! -L "$f" ]] || continue
    d="$(otool -l "$f" | awk '/cmd LC_LOAD_DYLIB$/{f=1;next} f&&$1=="name"{print $2;f=0}' | grep '^@loader_path/' | head -n 1 || true)"
    if [[ -n "$d" ]]; then victim="$f"; victim_dep="$d"; break; fi
done
if [[ -n "$victim" ]]; then
    # Point it at the real Homebrew copy when one exists, so the runtime check
    # below can also see dyld load it from outside the bundle.
    dep_name="$(basename "$victim_dep")"
    brew_dep=""
    if brew_prefix="$(brew --prefix 2>/dev/null)"; then
        for cand in "$brew_prefix"/opt/*/lib/"$dep_name"; do
            if [[ -e "$cand" ]]; then brew_dep="$cand"; break; fi
        done
    fi
    install_name_tool -change "$victim_dep" "${brew_dep:-/opt/homebrew/lib/$dep_name}" "$victim" 2>/dev/null || true
    codesign --force --sign - "$victim" 2>/dev/null || true
    expect_reject "absolute Homebrew dylib path in $(basename "$victim")" "$c"
    if [[ -n "$brew_dep" && "$victim" == "$c/bin/"* ]]; then
        if bad="$(foreign_images "$c" "$(basename "$victim")")" && [[ -n "$bad" ]]; then
            ok "runtime check rejects: $(basename "$victim") loads $(head -n 1 <<< "$bad")"
        else
            fail_test "runtime check accepted tampered $(basename "$victim")"
        fi
    fi
else
    echo "  ⏭️  no bundled dylib references to tamper with"
fi

# 2. a binary that requires a newer macOS than the floor
c="$(fresh_copy)"
vtool -set-build-version macos 26.0 26.0 -replace -output "$c/bin/lzip.new" "$c/bin/lzip" 2>/dev/null \
    && mv "$c/bin/lzip.new" "$c/bin/lzip" && codesign --force --sign - "$c/bin/lzip" 2>/dev/null
expect_reject "minos 26.0 on lzip" "$c"

# 3. an unexpected tool in bin/
c="$(fresh_copy)"
cp "$c/bin/lzip" "$c/bin/extra-tool"
expect_reject "extra tool in bin/" "$c"

### ================================
### SUMMARY
### ================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: $pass passed, $fail failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[[ "$fail" -eq 0 ]] || exit 1
