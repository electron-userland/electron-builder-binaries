#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./bundle-linux-libs.sh /path/to/osslsigncode /path/to/outdir
# Example:
#   ./bundle-linux-libs.sh ./win-codesign-linux-amd64/osslsigncode ./win-codesign-linux-amd64

BIN="$1"       # full path to the osslsigncode binary (or directory/bin)
OUTDIR="$2"    # top-level bundle dir (contains bin/ and lib/)
# If user passed directory, detect binary path:
if [[ -d "$BIN" ]]; then
  BIN_DIR="$BIN"
  BIN="$BIN_DIR/osslsigncode"
else
  BIN_DIR="$(dirname "$(readlink -f "$BIN")")"
fi

# canonicalize OUTDIR
OUTDIR="$(mkdir -p "$OUTDIR"; cd "$OUTDIR"; pwd -P)"
BIN_DIR="$(dirname "$(readlink -f "$BIN")")"
LIB_DIR="$OUTDIR/lib"
BIN_OUT_DIR="$OUTDIR/bin"

mkdir -p "$LIB_DIR" "$BIN_OUT_DIR"

echo "Bundling:"
echo "  binary:    $BIN"
echo "  outdir:    $OUTDIR"
echo "  lib dir:   $LIB_DIR"

# Helper: safe copy preserving symlinks & permissions (resolve source to file)
copy_lib() {
  local src="$1" dstname="$2"
  if [[ ! -e "$src" ]]; then
    echo "  ⚠️  source not found: $src"
    return 1
  fi
  echo "  📥 copy $src -> $LIB_DIR/$dstname"
  # -L resolve symlinks (we prefer real file), -p preserve mode
  cp -aL "$src" "$LIB_DIR/$dstname"
  chmod 644 "$LIB_DIR/$dstname" || true
  return 0
}

# ------------------------------------------------------------
# 1) Copy the binary into bundle/bin and set executable bit
# ------------------------------------------------------------
echo "  ➕ placing binary into bundle bin/"
cp -aL "$BIN" "$BIN_OUT_DIR/osslsigncode"
chmod 755 "$BIN_OUT_DIR/osslsigncode"

# ------------------------------------------------------------
# 2) Auto-detect direct shared deps via ldd (like original)
# ------------------------------------------------------------
echo "🔎 Detecting direct ELF deps with ldd..."
skip_regex='^(libc\.so|libm\.so|libdl\.so|libpthread\.so|librt\.so|ld-linux|linux-vdso|vdso)'

declare -A auto_allow=()

while IFS= read -r line; do
  # ldd line: libfoo.so.1 => /lib/... (0x...)
  if [[ "$line" =~ "=>" ]]; then
    libpath=$(awk '{print $3}' <<<"$line")
    [[ -z "$libpath" || "$libpath" == "not" ]] && continue
    [[ ! -f "$libpath" ]] && continue
    base=$(basename "$libpath")
    if [[ "$base" =~ $skip_regex ]]; then
      echo "  🔕 skip system: $base"
      continue
    fi
    auto_allow["$base"]="$libpath"
  fi
done < <(ldd "$BIN" 2>/dev/null || true)

# copy direct deps
for base in "${!auto_allow[@]}"; do
  src="${auto_allow[$base]}"
  copy_lib "$src" "$base" || true
done

# ------------------------------------------------------------
# 3) Detect whether binary wants OpenSSL 3 (libcrypto.so.3 / libssl.so.3)
#    fallback: inspect DT_NEEDED entries if ldd output didn't include .so.3
# ------------------------------------------------------------
echo "🔍 Checking whether binary expects OpenSSL 3..."

# function to scan DT_NEEDED via readelf or objdump
find_needed() {
  if command -v readelf >/dev/null 2>&1; then
    readelf -d "$BIN" 2>/dev/null | awk -F'[][]' '/NEEDED/{print $2}'
  elif command -v objdump >/dev/null 2>&1; then
    objdump -p "$BIN" 2>/dev/null | awk '/NEEDED/{print $2}'
  else
    return 1
  fi
}

needs_openssl3=false
while IFS= read -r need; do
  if [[ "$need" == libcrypto.so.3* || "$need" == libssl.so.3* ]]; then
    needs_openssl3=true
  fi
done < <(find_needed || true)

# If ldd already showed libcrypto.so.3, mark openssl3 true
if ldd "$BIN" 2>/dev/null | grep -q "libcrypto.so.3\|libssl.so.3"; then
  needs_openssl3=true
fi

if $needs_openssl3; then
  echo "✅ Binary requires OpenSSL 3 (providers required)"
else
  echo "ℹ️ Binary does not appear to require OpenSSL 3 (ok to ship OpenSSL 1.1 if that's preferred)"
fi

# ------------------------------------------------------------
# 4) If OpenSSL 3 required, locate libssl/libcrypto .so.3 and provider modules and copy them
# ------------------------------------------------------------
if $needs_openssl3; then
  echo "🔎 Locating OpenSSL 3 libs and provider modules (common locations)..."

  # helper to find a library path (ldconfig, pkg-config, common paths)
  find_lib() {
    local libname="$1"
    # try ldconfig -p
    if command -v ldconfig >/dev/null 2>&1; then
      ldconfig -p 2>/dev/null | awk -v lib="$libname" '$1 ~ lib {print $NF; exit}'
    fi
  }

  libcrypto_path="$(find_lib libcrypto.so.3 || true)"
  libssl_path="$(find_lib libssl.so.3 || true)"

  # fallback search common locations
  common_paths=( \
    "/usr/lib/$(uname -m)-linux-gnu" \
    "/usr/lib64" \
    "/usr/lib" \
    "/lib/x86_64-linux-gnu" \
    "/lib64" \
    "/lib" \
    "/usr/local/lib" \
  )

  for p in "${common_paths[@]}"; do
    [[ -z "$libcrypto_path" && -f "$p/libcrypto.so.3" ]] && libcrypto_path="$p/libcrypto.so.3"
    [[ -z "$libssl_path"   && -f "$p/libssl.so.3"   ]] && libssl_path="$p/libssl.so.3"
  done

  if [[ -n "$libcrypto_path" ]]; then
    copy_lib "$libcrypto_path" "libcrypto.so.3" || true
  else
    echo "  ⚠️ Could not find system libcrypto.so.3 (copying libcrypto.so.1.1 won't satisfy OpenSSL 3 expectations)"
  fi

  if [[ -n "$libssl_path" ]]; then
    copy_lib "$libssl_path" "libssl.so.3" || true
  else
    echo "  ⚠️ Could not find system libssl.so.3"
  fi

  # locate provider module directory - common names: ossl-modules, providers
  provider_dirs=()
  if [[ -n "$libcrypto_path" ]]; then
    base_dir="$(dirname "$(readlink -f "$libcrypto_path")")"
    provider_dirs+=( "$base_dir/ossl-modules" "$base_dir/providers" )
  fi

  # also check standard locations
  provider_dirs+=( "/usr/lib/ossl-modules" "/usr/lib/x86_64-linux-gnu/ossl-modules" "/usr/lib64/ossl-modules" "/usr/lib64/openssl-3/ossl-modules" )

  providers_found=false
  for pd in "${provider_dirs[@]}"; do
    if [[ -d "$pd" ]]; then
      echo "  📦 copying provider modules from $pd"
      mkdir -p "$LIB_DIR/ossl-modules"
      cp -aL "$pd"/*.so "$LIB_DIR/ossl-modules/" 2>/dev/null || true
      providers_found=true
      break
    fi
  done

  if ! $providers_found; then
    # try searching the filesystem for libdefault.so (best-effort; may be slow)
    if command -v find >/dev/null 2>&1; then
      echo "  🔎 attempting longer search for libdefault.so (may be slow)..."
      found="$(find /usr /lib /usr/local -maxdepth 4 -type f -name 'libdefault.so' 2>/dev/null | head -n1 || true)"
      if [[ -n "$found" ]]; then
        pd="$(dirname "$found")"
        echo "  📦 copying provider modules from $pd"
        mkdir -p "$LIB_DIR/ossl-modules"
        cp -aL "$pd"/*.so "$LIB_DIR/ossl-modules/" 2>/dev/null || true
        providers_found=true
      fi
    fi
  fi

  if ! $providers_found; then
    echo "  ⚠️ WARNING: Could not locate OpenSSL 3 provider modules. The binary may fail at runtime."
    echo "           On Debian/Ubuntu they typically live under /usr/lib/x86_64-linux-gnu/ossl-modules/"
  fi
fi

# ------------------------------------------------------------
# 5) Set rpath on bundled binary and on copied libs
# ------------------------------------------------------------
echo "🔧 Setting RPATHs with patchelf..."
if ! command -v patchelf >/dev/null 2>&1; then
  echo "  ❌ patchelf not installed. Install patchelf and rerun. Skipping RPATH patch."
else
  # set binary rpath to $ORIGIN/../lib so it will load our library dir
  echo "  ➤ setting binary RPATH to \$ORIGIN/../lib"
  patchelf --set-rpath '$ORIGIN/../lib' "$BIN_OUT_DIR/osslsigncode" || true

  # set copied libs rpath to $ORIGIN (so libs can load providers in $ORIGIN/ossl-modules)
  for libfile in "$LIB_DIR"/*; do
    [[ ! -f "$libfile" ]] && continue
    # skip non-ELF files
    if file "$libfile" | grep -q 'ELF'; then
      echo "  ➤ setting rpath on $(basename "$libfile") to \$ORIGIN"
      patchelf --set-rpath '$ORIGIN' "$libfile" 2>/dev/null || true
    fi
  done
fi

# ------------------------------------------------------------
# 6) Create a small runtime wrapper script that sets env vars
# ------------------------------------------------------------
WRAPPER="$BIN_OUT_DIR/osslsigncode-run"
cat > "$WRAPPER" <<'EOF'
#!/usr/bin/env bash
# Runtime wrapper to ensure bundle's libs and OpenSSL modules are used.
# Usage: ./osslsigncode-run [args...]

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
export LD_LIBRARY_PATH="$HERE/lib:${LD_LIBRARY_PATH:-}"
# If you have ossl-modules copied into lib/ossl-modules, set OPENSSL_MODULES
if [[ -d "$HERE/lib/ossl-modules" ]]; then
  export OPENSSL_MODULES="$HERE/lib/ossl-modules"
fi
exec "$HERE/bin/osslsigncode" "$@"
EOF
chmod +x "$WRAPPER"

echo "✅ Bundle complete."
echo "  - Launch binary via: $WRAPPER --version"
echo "  - Or run: LD_LIBRARY_PATH=$OUTDIR/lib OPENSSL_MODULES=$OUTDIR/lib/ossl-modules $OUTDIR/bin/osslsigncode"
