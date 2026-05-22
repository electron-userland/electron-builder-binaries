#!/usr/bin/env bash
set -euo pipefail

### ================================
### ARGS
### ================================
BUNDLE_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bundle-dir) BUNDLE_DIR="$2"; shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

if [[ -z "$BUNDLE_DIR" ]]; then
    echo "Usage: $0 --bundle-dir <path-to-extracted-bundle>"
    exit 1
fi

if [[ ! -d "$BUNDLE_DIR/bin" ]]; then
    echo "❌ No bin/ directory found in $BUNDLE_DIR"
    exit 1
fi

BIN="$BUNDLE_DIR/bin"
LIB="$BUNDLE_DIR/lib"

# Use bundled dylibs, not system/Homebrew ones
export DYLD_FALLBACK_LIBRARY_PATH="$LIB${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"

### ================================
### HELPERS
### ================================
pass=0
fail=0

ok() {
    echo "  ✅ $1"
    pass=$((pass + 1))
}

fail_bin() {
    echo "  ❌ $1"
    fail=$((fail + 1))
}

run_test() {
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then
        ok "$label"
    else
        fail_bin "$label"
    fi
}

# Check a binary exists and is executable
assert_exists() {
    local bin="$BIN/$1"
    if [[ ! -x "$bin" ]]; then
        fail_bin "$1 (missing or not executable)"
        return 1
    fi
    return 0
}

# Verify no absolute Homebrew paths remain in a binary's load commands
check_paths() {
    local label="$1"
    local bin="$BIN/$2"
    local bad
    bad="$(otool -L "$bin" 2>/dev/null | awk 'NR>1 {print $1}' | grep -E '^/(opt/homebrew|usr/local)' || true)"
    if [[ -n "$bad" ]]; then
        fail_bin "$label (absolute Homebrew paths found: $bad)"
    else
        ok "$label (no absolute paths)"
    fi
}

### ================================
### BINARY TESTS
### ================================
echo "🧪 Testing linux-tools bundle at: $BUNDLE_DIR"
echo ""

echo "── gnu-tar ──"
assert_exists gtar && run_test "gtar --version" "$BIN/gtar" --version
check_paths "gtar paths" gtar

echo ""
echo "── lzip ──"
assert_exists lzip && run_test "lzip --version" "$BIN/lzip" --version
check_paths "lzip paths" lzip

echo ""
echo "── makedepend ──"
assert_exists makedepend && run_test "makedepend (no args, expect non-crash)" bash -c "'$BIN/makedepend' || true"
check_paths "makedepend paths" makedepend

echo ""
echo "── glib ──"
assert_exists gdbus           && run_test "gdbus --help"                          "$BIN/gdbus" --help
assert_exists gdbus-codegen   && run_test "gdbus-codegen --help"                  "$BIN/gdbus-codegen" --help
assert_exists gio             && run_test "gio version"                           "$BIN/gio" version
assert_exists gio-querymodules && run_test "gio-querymodules (no crash)" bash -c "'$BIN/gio-querymodules' /nonexistent 2>/dev/null || true"
assert_exists glib-compile-resources && run_test "glib-compile-resources --version" "$BIN/glib-compile-resources" --version
assert_exists glib-compile-schemas   && run_test "glib-compile-schemas --version"   "$BIN/glib-compile-schemas" --version
assert_exists glib-genmarshal        && run_test "glib-genmarshal --version"         "$BIN/glib-genmarshal" --version
assert_exists glib-gettextize        && run_test "glib-gettextize --version" bash -c "'$BIN/glib-gettextize' --version 2>/dev/null || true"
assert_exists glib-mkenums           && run_test "glib-mkenums --version"            "$BIN/glib-mkenums" --version
assert_exists gobject-query          && run_test "gobject-query (no crash)" bash -c "'$BIN/gobject-query' --help 2>/dev/null || true"
assert_exists gresource              && run_test "gresource --help"                  "$BIN/gresource" --help
assert_exists gsettings              && run_test "gsettings --help"                  "$BIN/gsettings" --help
assert_exists gtester                && run_test "gtester --version"                 "$BIN/gtester" --version
assert_exists gtester-report         && run_test "gtester-report (no crash)" bash -c "'$BIN/gtester-report' --help 2>/dev/null || true"
check_paths "gdbus paths" gdbus
check_paths "gio paths" gio
check_paths "glib-compile-schemas paths" glib-compile-schemas

echo ""
echo "── libgsf ──"
assert_exists gsf && run_test "gsf (no crash)" bash -c "'$BIN/gsf' --help 2>/dev/null || true"
check_paths "gsf paths" gsf

echo ""
echo "── libtool ──"
assert_exists glibtool     && run_test "glibtool --version"     "$BIN/glibtool" --version
assert_exists glibtoolize  && run_test "glibtoolize --version"  "$BIN/glibtoolize" --version
check_paths "glibtool paths" glibtool

echo ""
echo "── pcre ──"
assert_exists pcre-config  && run_test "pcre-config --version"  "$BIN/pcre-config" --version
assert_exists pcregrep     && run_test "pcregrep --version"     "$BIN/pcregrep" --version
assert_exists pcretest     && run_test "pcretest --version"      "$BIN/pcretest" --version
check_paths "pcregrep paths" pcregrep

echo ""
echo "── gettext ──"
assert_exists gettext   && run_test "gettext --version"   "$BIN/gettext" --version
assert_exists msgfmt    && run_test "msgfmt --version"    "$BIN/msgfmt" --version
assert_exists msgmerge  && run_test "msgmerge --version"  "$BIN/msgmerge" --version
assert_exists envsubst  && run_test "envsubst --version"  "$BIN/envsubst" --version
assert_exists xgettext  && run_test "xgettext --version"  "$BIN/xgettext" --version
check_paths "msgfmt paths" msgfmt

echo ""
echo "── binutils ──"
assert_exists gar  && run_test "gar --version"  "$BIN/gar" --version
assert_exists ar   && run_test "ar --version"   "$BIN/ar" --version
check_paths "ar paths" ar

### ================================
### SUMMARY
### ================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: $pass passed, $fail failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[[ "$fail" -eq 0 ]] || exit 1
