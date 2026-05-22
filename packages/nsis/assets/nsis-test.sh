#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# NSIS Bundle Test Suite
# =============================================================================
# Usage: nsis-test.sh [--bundle-dir PATH] [--full]
#
# --bundle-dir PATH  Path to extracted nsis-bundle directory.
#                    Defaults to ./out/nsis/nsis-bundle relative to this script.
#
# --full             Enable the optional end-to-end install + uninstall test (Test 15).
#                    Requires Windows or Linux+Wine to execute the installer.
#
# Exit code 0 = all non-skipped tests passed.
# =============================================================================

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BUNDLE_DIR="$SCRIPT_DIR/../out/nsis/nsis-bundle"
FULL_TEST=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bundle-dir) BUNDLE_DIR="${2:-}"; shift 2 ;;
        --full)       FULL_TEST="--full"; shift ;;
        *) echo "❌ Unknown option: $1"; exit 1 ;;
    esac
done

BUNDLE_DIR=$(cd "$BUNDLE_DIR" && pwd)

PASS=0
FAIL=0
SKIP=0
TMPDIR_TEST=$(mktemp -d)

cleanup() { rm -rf "$TMPDIR_TEST"; }
trap cleanup EXIT INT TERM

# =============================================================================
# OS + arch detection
# =============================================================================

IS_WINDOWS=false
IS_MAC=false
IS_LINUX=false
case "$(uname -s)" in
    Darwin*)              IS_MAC=true ;;
    Linux*)               IS_LINUX=true ;;
    MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=true ;;
esac
[ "${OS:-}" = "Windows_NT" ] && IS_WINDOWS=true

ARCH=$(uname -m 2>/dev/null || echo "unknown")
case "$ARCH" in
    x86_64|amd64)  ARCH_DIR="x64" ;;
    arm64|aarch64) ARCH_DIR="arm64" ;;
    *)             ARCH_DIR="$ARCH" ;;
esac

# =============================================================================
# Helpers
# =============================================================================

pass()  { echo "[PASS] $*"; PASS=$((PASS + 1)); }
fail()  { echo "[FAIL] $*"; FAIL=$((FAIL + 1)); }
skip()  { echo "[SKIP] $*"; SKIP=$((SKIP + 1)); }

assert_dir()  { [ -d "$1" ] && pass "$2" || fail "$2 (missing dir: $1)"; }
assert_file() { [ -f "$1" ] && pass "$2" || fail "$2 (missing file: $1)"; }

assert_patch() {
    local file="$1" label="$2"
    if grep -q "BEGIN FIXES ADDED" "$file" 2>/dev/null; then
        pass "$label: language patch applied"
    else
        fail "$label: language patch marker missing (fixes not applied)"
    fi
}

# Run the makensis bash wrapper (handles executable bit or bash fallback)
run_wrapper() {
    local bin="$1"; shift
    if [ -x "$bin" ]; then "$bin" "$@"; else bash "$bin" "$@"; fi
}

# =============================================================================
# Header
# =============================================================================

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  NSIS Bundle Test Suite"
echo "═══════════════════════════════════════════════════════════════"
echo "  Bundle:   $BUNDLE_DIR"
echo "  OS:       $(uname -s) / $ARCH"
E2E_STATUS="disabled (pass --full to enable)"
[ -n "$FULL_TEST" ] && E2E_STATUS="enabled (--full)"
echo "  Full E2E: $E2E_STATUS"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# =============================================================================
# TEST 1 — Bundle structure
# =============================================================================

echo "── Test 1: Bundle structure ────────────────────────────────────"

assert_dir  "$BUNDLE_DIR/windows"      "windows/ present"
assert_dir  "$BUNDLE_DIR/linux"        "linux/ present"
assert_dir  "$BUNDLE_DIR/mac"          "mac/ present"
assert_file "$BUNDLE_DIR/makensis"     "makensis wrapper present"
assert_file "$BUNDLE_DIR/makensis.cmd" "makensis.cmd present"
assert_file "$BUNDLE_DIR/makensis.ps1" "makensis.ps1 present"

# =============================================================================
# TEST 2 — Binary presence
# All Linux binaries (x64 + arm64) are always required in the bundle regardless
# of host platform. macOS: native arch is required; opposite arch is opportunistic.
# =============================================================================

echo ""
echo "── Test 2: Binary presence ─────────────────────────────────────"

assert_file "$BUNDLE_DIR/windows/makensisw.exe"         "windows/makensisw.exe present"
assert_file "$BUNDLE_DIR/windows/makensis.exe"          "windows/makensis.exe (console stub) present"
assert_file "$BUNDLE_DIR/windows/Bin/makensis.exe"      "windows/Bin/makensis.exe (strlen-patched) present"
assert_file "$BUNDLE_DIR/linux/x64/makensis"            "linux/x64/makensis present"
assert_file "$BUNDLE_DIR/linux/arm64/makensis"          "linux/arm64/makensis present"
assert_file "$BUNDLE_DIR/elevate.exe"              "elevate.exe present at bundle root"

if [ -f "$BUNDLE_DIR/elevate.exe" ]; then
    MZ_ELV=$(od -N 2 -A n -t x1 "$BUNDLE_DIR/elevate.exe" 2>/dev/null | tr -d ' \n')
    if [ "$MZ_ELV" = "4d5a" ]; then
        pass "elevate.exe: valid PE binary (MZ header)"
    else
        fail "elevate.exe: invalid MZ header (got: $MZ_ELV)"
    fi
fi

if $IS_MAC; then
    # Current arch is required; opposite arch is opportunistic
    assert_file "$BUNDLE_DIR/mac/$ARCH_DIR/makensis" "mac/$ARCH_DIR/makensis present"
    OTHER_ARCH="arm64"; [ "$ARCH_DIR" = "arm64" ] && OTHER_ARCH="x64"
    if [ -f "$BUNDLE_DIR/mac/$OTHER_ARCH/makensis" ]; then
        pass "mac/$OTHER_ARCH/makensis present (multi-arch build)"
    else
        skip "mac/$OTHER_ARCH/makensis absent (single-arch build)"
    fi
fi

# =============================================================================
# TEST 3 — Binary format
# Required on the native OS; no skipping.
# =============================================================================

echo ""
echo "── Test 3: Binary format ───────────────────────────────────────"

if $IS_LINUX; then
    for linux_arch in x64 arm64; do
        linux_bin="$BUNDLE_DIR/linux/$linux_arch/makensis"
        if [ -f "$linux_bin" ]; then
            if command -v file &>/dev/null; then
                FILE_OUT=$(file "$linux_bin")
                if echo "$FILE_OUT" | grep -q "ELF"; then
                    pass "linux/$linux_arch/makensis: valid ELF binary"
                else
                    fail "linux/$linux_arch/makensis: not ELF (got: $FILE_OUT)"
                fi
            else
                # od fallback: ELF magic = 7f 45 4c 46
                ELF_MAGIC=$(od -N 4 -A n -t x1 "$linux_bin" 2>/dev/null | tr -d ' \n')
                if [ "$ELF_MAGIC" = "7f454c46" ]; then
                    pass "linux/$linux_arch/makensis: valid ELF binary (magic bytes)"
                else
                    fail "linux/$linux_arch/makensis: ELF magic check failed (got: '$ELF_MAGIC')"
                fi
            fi
        else
            fail "linux/$linux_arch/makensis: file not found"
        fi
    done
fi

if $IS_MAC; then
    MAC_BIN="$BUNDLE_DIR/mac/$ARCH_DIR/makensis"
    [ -f "$MAC_BIN" ] || MAC_BIN="$BUNDLE_DIR/mac/makensis"
    if command -v file &>/dev/null; then
        FILE_OUT=$(file "$MAC_BIN")
        if echo "$FILE_OUT" | grep -q "Mach-O"; then
            pass "mac/$ARCH_DIR/makensis: valid Mach-O binary"
        else
            fail "mac/$ARCH_DIR/makensis: not Mach-O (got: $FILE_OUT)"
        fi
    else
        # od fallback: Mach-O magics (little-endian 32/64bit or fat binary)
        MAC_MAGIC=$(od -N 4 -A n -t x1 "$MAC_BIN" 2>/dev/null | tr -d ' \n')
        if echo "$MAC_MAGIC" | grep -qE "^(cefaedfe|cffaedfe|cafebabe)"; then
            pass "mac/$ARCH_DIR/makensis: valid Mach-O binary (magic bytes)"
        else
            fail "mac/$ARCH_DIR/makensis: Mach-O magic check failed (got: '$MAC_MAGIC')"
        fi
    fi
fi

if $IS_WINDOWS; then
    # PE magic = MZ = 4d 5a — check the actual compiler (makensisw.exe)
    _bin_path="$BUNDLE_DIR/windows/makensisw.exe"
    MZ=$(od -N 2 -A n -t x1 "$_bin_path" 2>/dev/null | tr -d ' \n')
    if [ "$MZ" = "4d5a" ]; then
        pass "windows/makensisw.exe: valid PE binary (MZ header)"
    elif command -v pwsh &>/dev/null; then
        WIN_MKS=$(cygpath -w "$_bin_path" 2>/dev/null || echo "$_bin_path")
        MZ_PS=$(pwsh -NoProfile -Command \
            "[System.IO.File]::ReadAllBytes('$WIN_MKS')[0] -eq 77" 2>/dev/null | tr -d '\r')
        if [ "$MZ_PS" = "True" ]; then
            pass "windows/makensisw.exe: valid PE binary (MZ header via PowerShell)"
        else
            fail "windows/makensisw.exe: MZ header check failed"
        fi
    else
        fail "windows/makensisw.exe: cannot verify PE header (od and pwsh both unavailable)"
    fi
fi

# =============================================================================
# TEST 4 — NSISDIR data files
# =============================================================================

echo ""
echo "── Test 4: NSISDIR data files ──────────────────────────────────"

assert_dir  "$BUNDLE_DIR/windows/Bin"                 "windows/Bin present"
assert_dir  "$BUNDLE_DIR/windows/Contrib"             "windows/Contrib present"
assert_dir  "$BUNDLE_DIR/windows/Include"             "windows/Include present"
assert_dir  "$BUNDLE_DIR/windows/Plugins"             "windows/Plugins present"
assert_dir  "$BUNDLE_DIR/windows/Stubs"               "windows/Stubs present"
assert_dir  "$BUNDLE_DIR/windows/Plugins/x86-ansi"    "Plugins/x86-ansi present"
assert_dir  "$BUNDLE_DIR/windows/Plugins/x86-unicode" "Plugins/x86-unicode present"
assert_file "$BUNDLE_DIR/windows/makensisw.exe"       "windows/makensisw.exe present"
assert_file "$BUNDLE_DIR/windows/nsisconf.nsh"        "windows/nsisconf.nsh present"

# =============================================================================
# TEST 5 — Language files: assert every file by name + verify patches
# =============================================================================

echo ""
echo "── Test 5: Language files ──────────────────────────────────────"

LANG_DIR="$BUNDLE_DIR/windows/Contrib/Language files"
assert_dir "$LANG_DIR" "Contrib/Language files/ present"

LANG_NAMES=(
    Afrikaans Albanian Arabic Armenian Asturian Basque Belarusian Bosnian Breton
    Bulgarian Catalan Corsican Croatian Czech Danish Dutch English
    Esperanto Estonian Farsi Finnish French Galician Georgian German Greek Hebrew
    Hindi Hungarian Icelandic Indonesian Irish Italian Japanese Korean
    Kurdish Latvian Lithuanian Luxembourgish Macedonian Malay Mongolian
    Norwegian NorwegianNynorsk Pashto Polish Portuguese PortugueseBR Romanian
    Russian ScotsGaelic Serbian SerbianLatin SimpChinese Slovak Slovenian Spanish
    SpanishInternational Swedish Tatar Thai TradChinese Turkish Ukrainian
    Uzbek Vietnamese Welsh
)

for lang in "${LANG_NAMES[@]}"; do
    assert_file "$LANG_DIR/${lang}.nlf" "${lang}.nlf present"
    assert_file "$LANG_DIR/${lang}.nsh" "${lang}.nsh present"
done

# Verify patch markers for the 5 .nsh-patched languages
for lang in Finnish Hungarian Korean Thai Turkish; do
    [ -f "$LANG_DIR/${lang}.nsh" ] && assert_patch "$LANG_DIR/${lang}.nsh" "${lang}.nsh"
done

# Verify patch marker for the 1 .nlf-patched language
[ -f "$LANG_DIR/SimpChinese.nlf" ] && assert_patch "$LANG_DIR/SimpChinese.nlf" "SimpChinese.nlf"

# =============================================================================
# TEST 6 — Plugin DLLs: assert every base DLL by name in both archs
# =============================================================================

echo ""
echo "── Test 6: Plugin DLLs ─────────────────────────────────────────"

BASE_DLLS=(
    AdvSplash.dll
    Banner.dll
    BgImage.dll
    Dialer.dll
    InstallOptions.dll
    LangDLL.dll
    Math.dll
    NSISdl.dll
    Splash.dll
    StartMenu.dll
    System.dll
    TypeLib.dll
    UserInfo.dll
    VPatch.dll
    nsDialogs.dll
    nsExec.dll
)

for arch_dir in x86-unicode x86-ansi; do
    for dll in "${BASE_DLLS[@]}"; do
        assert_file "$BUNDLE_DIR/windows/Plugins/$arch_dir/$dll" \
            "Plugins/$arch_dir/$dll present"
    done
done

# Validate each DLL is a genuine Windows PE (MZ magic bytes)
for arch_dir in x86-unicode x86-ansi; do
    for dll in "${BASE_DLLS[@]}"; do
        dll_path="$BUNDLE_DIR/windows/Plugins/$arch_dir/$dll"
        if [ -f "$dll_path" ]; then
            MZ_DLL=$(od -N 2 -A n -t x1 "$dll_path" 2>/dev/null | tr -d ' \n')
            if [ "$MZ_DLL" = "4d5a" ]; then
                pass "Plugins/$arch_dir/$dll valid MZ header"
            else
                fail "Plugins/$arch_dir/$dll invalid or missing MZ header"
            fi
        else
            skip "Plugins/$arch_dir/$dll not found (existence checked above)"
        fi
    done
done

# =============================================================================
# Set up the wrapper for compile tests 7-15
# =============================================================================

WRAPPER="$BUNDLE_DIR/makensis"
chmod +x "$WRAPPER" 2>/dev/null || true

# =============================================================================
# TEST 7 — Version flag
# =============================================================================

echo ""
echo "── Test 7: Version flag ────────────────────────────────────────"

if VERSION_OUT=$(run_wrapper "$WRAPPER" -VERSION 2>&1); then
    # Accept release tags (v3.12) and CVS date strings from source builds (20-May-2026.cvs)
    if echo "$VERSION_OUT" | grep -qiE "v?3\.[0-9]|[0-9]+-[A-Za-z]+-[0-9]{4}"; then
        pass "Version flag: $(echo "$VERSION_OUT" | tr -d '\r\n')"
    else
        fail "Version flag: unexpected output: $VERSION_OUT"
    fi
else
    fail "Version flag: wrapper exited non-zero (output: $(echo "$VERSION_OUT" | tr -d '\r\n'))"
fi

# =============================================================================
# TEST 8 — Minimal compile
# =============================================================================

echo ""
echo "── Test 8: Minimal compile ─────────────────────────────────────"

cat > "$TMPDIR_TEST/minimal.nsi" <<'NSI'
Name "Minimal"
OutFile "minimal.exe"
InstallDir "$TEMP\MinimalTest"
Section
SectionEnd
NSI

cd "$TMPDIR_TEST"
echo "  [cmd] $WRAPPER minimal.nsi"
_t8_start=$(date +%s 2>/dev/null || echo 0)
# Run without output capture so PS1 Write-Output lines appear live in CI logs
if run_wrapper "$WRAPPER" "minimal.nsi"; then
    _t8_rc=0
else
    _t8_rc=$?
fi
_t8_end=$(date +%s 2>/dev/null || echo 0)
echo "  [rc]  $_t8_rc  elapsed: $(( _t8_end - _t8_start ))s"
if [ $_t8_rc -eq 0 ] && [ -f "minimal.exe" ]; then
    pass "Minimal compile: minimal.exe produced"
else
    echo "  [exe] $([ -f minimal.exe ] && echo present || echo MISSING)"
    fail "Minimal compile: exit=$_t8_rc"
fi

# =============================================================================
# TEST 9 — MUI2 compile (exercises Include/ + Contrib/ resolution via NSISDIR)
# =============================================================================

echo ""
echo "── Test 9: MUI2 compile ────────────────────────────────────────"

cat > "$TMPDIR_TEST/mui2.nsi" <<'NSI'
!include "MUI2.nsh"

Name "MUI2 Test"
OutFile "mui2-installer.exe"
InstallDir "$TEMP\MUI2Test"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_LANGUAGE "English"

Section "Main"
  SetOutPath "$INSTDIR"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
SectionEnd

Section "Uninstall"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
SectionEnd
NSI

cd "$TMPDIR_TEST"
if run_wrapper "$WRAPPER" "mui2.nsi" >/dev/null 2>&1 && [ -f "mui2-installer.exe" ]; then
    pass "MUI2 compile: mui2-installer.exe produced"
else
    fail "MUI2 compile: failed (NSISDIR or Include resolution failure)"
fi

# =============================================================================
# TEST 10 — strlen_8192 patch verification
# =============================================================================

echo ""
echo "── Test 10: strlen_8192 ────────────────────────────────────────"

LONG_STR=$(printf 'A%.0s' {1..8000})

cat > "$TMPDIR_TEST/strlen.nsi" <<NSI
Name "StrLen Test"
OutFile "strlen-test.exe"
InstallDir "\$TEMP\StrLenTest"

!define LONG_STRING "$LONG_STR"

Section
  DetailPrint "\${LONG_STRING}"
SectionEnd
NSI

cd "$TMPDIR_TEST"
STRLEN_OUT=$(run_wrapper "$WRAPPER" "strlen.nsi" 2>&1 || true)
if echo "$STRLEN_OUT" | grep -qi "string too long\|overflow"; then
    fail "strlen_8192: string overflow error (patch not applied)"
elif [ -f "strlen-test.exe" ]; then
    pass "strlen_8192: 8000-char string compiled without overflow"
else
    fail "strlen_8192: compile failed: $STRLEN_OUT"
fi

# =============================================================================
# TEST 11 — Plugin DLL compile smoke test
# =============================================================================

echo ""
echo "── Test 11: Plugin DLL compile smoke test ──────────────────────"

cat > "$TMPDIR_TEST/plugin-smoke.nsi" <<'NSI'
Name "Plugin DLL Smoke Test"
OutFile "plugin-smoke.exe"
InstallDir "$TEMP\NSISPluginSmokeTest"
SilentInstall silent

; Each Plugin::Function call causes makensis to locate the DLL,
; read its PE export table, and embed it. Installer is never executed.
Section "Main"
  nsExec::Exec 'echo test'
  Pop $0
  Math::Script 'var x=1;'
  System::Call 'kernel32::GetTickCount()i'
  Pop $0
  UserInfo::GetAccountType
  Pop $0
  StartMenu::Select /autoadd /noicon "$SMPROGRAMS\Test" "Test"
  Pop $0
  TypeLib::Register "$SYSDIR\stdole2.tlb"
  Pop $0
  VPatch::GetFileCRC32 "$EXEPATH" $0
  AdvSplash::show /NOUNLOAD 1000 1000 0 "$PLUGINSDIR\splash" "" ""
  Banner::show /NOUNLOAD /set 76 "Smoke Test" "Testing..."
  Banner::destroy
  BgImage::Destroy /RESET
  Splash::show /NOUNLOAD 1000 "$PLUGINSDIR\splash" "none"
  nsDialogs::Create 1018
  Pop $0
  InstallOptions::dialog "$PLUGINSDIR\test.ini"
  LangDLL::LangDialog "Smoke Test" "" "English" "English"
  Dialer::AttemptConnect
  NSISdl::download "http://localhost" "$TEMP\noop.tmp"
SectionEnd
NSI

cd "$TMPDIR_TEST"
SMOKE_OUT=$(run_wrapper "$WRAPPER" "plugin-smoke.nsi" 2>&1 || true)
if [ -f "plugin-smoke.exe" ]; then
    pass "Plugin smoke compile: all 16 plugin DLLs loaded and embedded"
else
    fail "Plugin smoke compile: failed — $SMOKE_OUT"
fi

# =============================================================================
# TEST 12 — Direct binary + explicit NSISDIR (Linux/macOS only)
# =============================================================================

echo ""
echo "── Test 12: Direct binary + explicit NSISDIR ───────────────────"

if $IS_LINUX; then
    for linux_arch in x64 arm64; do
        linux_direct="$BUNDLE_DIR/linux/$linux_arch/makensis"
        if [ ! -f "$linux_direct" ]; then
            fail "Direct binary linux/$linux_arch + NSISDIR: binary not found"
            continue
        fi
        chmod +x "$linux_direct" 2>/dev/null || true
        cat > "$TMPDIR_TEST/direct-${linux_arch}.nsi" <<NSI
Name "Direct"
OutFile "direct-${linux_arch}-test.exe"
InstallDir "\$TEMP\DirectTest"
Section
SectionEnd
NSI
        cd "$TMPDIR_TEST"
        _direct_out=$(NSISDIR="$BUNDLE_DIR/windows" "$linux_direct" "direct-${linux_arch}.nsi" 2>&1 || true)
        if [ -f "direct-${linux_arch}-test.exe" ]; then
            pass "Direct binary linux/$linux_arch + NSISDIR: compiled successfully"
        elif echo "$_direct_out" | grep -qi "exec format\|cannot execute"; then
            skip "Direct binary linux/$linux_arch + NSISDIR: cross-arch (QEMU not available)"
        else
            fail "Direct binary linux/$linux_arch + NSISDIR: $_direct_out"
        fi
    done
elif $IS_MAC; then
    DIRECT_BIN="$BUNDLE_DIR/mac/$ARCH_DIR/makensis"
    [ -f "$DIRECT_BIN" ] || DIRECT_BIN="$BUNDLE_DIR/mac/makensis"
    chmod +x "$DIRECT_BIN" 2>/dev/null || true
    cat > "$TMPDIR_TEST/direct.nsi" <<'NSI'
Name "Direct"
OutFile "direct-test.exe"
InstallDir "$TEMP\DirectTest"
Section
SectionEnd
NSI
    cd "$TMPDIR_TEST"
    if NSISDIR="$BUNDLE_DIR/windows" "$DIRECT_BIN" "direct.nsi" >/dev/null 2>&1 \
       && [ -f "direct-test.exe" ]; then
        pass "Direct binary mac/$ARCH_DIR + NSISDIR: compiled successfully"
    else
        fail "Direct binary mac/$ARCH_DIR + NSISDIR: binary returned non-zero or no output"
    fi
else
    skip "Direct binary + NSISDIR: no native binary for this platform (Windows)"
fi

# =============================================================================
# TEST 13 — makensis.cmd (Windows only)
# =============================================================================

echo ""
echo "── Test 13: makensis.cmd (Windows) ─────────────────────────────"

if $IS_WINDOWS; then
    cat > "$TMPDIR_TEST/cmd.nsi" <<'NSI'
Name "CMD"
OutFile "cmd-test.exe"
InstallDir "$TEMP\CMDTest"
Section
SectionEnd
NSI
    cd "$TMPDIR_TEST"
    CMD_BIN="$BUNDLE_DIR/makensis.cmd"
    # Run .cmd directly — MSYS2/Git Bash launches it via cmd.exe with path conversion
    if "$CMD_BIN" "cmd.nsi" >/dev/null 2>&1 && [ -f "cmd-test.exe" ]; then
        pass "makensis.cmd: compiled successfully"
    else
        fail "makensis.cmd: failed"
    fi
else
    skip "makensis.cmd: not Windows"
fi

# =============================================================================
# TEST 14 — makensis.ps1 (Windows only)
# =============================================================================

echo ""
echo "── Test 14: makensis.ps1 (Windows) ─────────────────────────────"

if $IS_WINDOWS; then
    cat > "$TMPDIR_TEST/ps1.nsi" <<'NSI'
Name "PS1"
OutFile "ps1-test.exe"
InstallDir "$TEMP\PS1Test"
Section
SectionEnd
NSI
    cd "$TMPDIR_TEST"
    PS1_BIN="$BUNDLE_DIR/makensis.ps1"
    if command -v pwsh &>/dev/null; then
        if pwsh -ExecutionPolicy Bypass -File "$PS1_BIN" "ps1.nsi" >/dev/null 2>&1 \
           && [ -f "ps1-test.exe" ]; then
            pass "makensis.ps1: compiled successfully"
        else
            fail "makensis.ps1: failed"
        fi
    else
        skip "makensis.ps1: pwsh not available"
    fi
else
    skip "makensis.ps1: not Windows"
fi

# =============================================================================
# TEST 15 — End-to-end install + uninstall  (optional: pass --full)
# =============================================================================

echo ""
echo "── Test 15: E2E install + uninstall ────────────────────────────"

if [ "$FULL_TEST" != "--full" ]; then
    skip "E2E installer: pass --full to enable this test"
else
    # Write a self-contained installer:
    #   - SilentInstall silent  → no UI, no /S flag needed
    #   - Writes INSTALLED.txt + Uninstall.exe to $TEMP\NsisE2ETest
    #   - Uninstall section cleans up completely
    cat > "$TMPDIR_TEST/e2e.nsi" <<'NSI'
Name "NSIS E2E Test"
OutFile "e2e-installer.exe"
InstallDir "$TEMP\NsisE2ETest"
SilentInstall silent

Section "Install"
  SetOutPath "$INSTDIR"
  FileOpen $0 "$INSTDIR\INSTALLED.txt" w
  FileWrite $0 "nsis-e2e-installed"
  FileClose $0
  WriteUninstaller "$INSTDIR\Uninstall.exe"
SectionEnd

Section "Uninstall"
  Delete "$INSTDIR\INSTALLED.txt"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
SectionEnd
NSI

    cd "$TMPDIR_TEST"
    if run_wrapper "$WRAPPER" "e2e.nsi" >/dev/null 2>&1 && [ -f "e2e-installer.exe" ]; then
        pass "E2E compile: e2e-installer.exe produced"
    else
        fail "E2E compile: failed to produce e2e-installer.exe"
    fi

    if [ -f "$TMPDIR_TEST/e2e-installer.exe" ]; then
        # Determine how to execute the installer
        RUN_CMD=()
        CAN_RUN=false

        if $IS_WINDOWS; then
            CAN_RUN=true
            RUN_CMD=("$TMPDIR_TEST/e2e-installer.exe")
        elif $IS_LINUX && command -v wine &>/dev/null; then
            CAN_RUN=true
            RUN_CMD=(wine "$TMPDIR_TEST/e2e-installer.exe")
        fi

        if $CAN_RUN; then
            # Run installer (SilentInstall silent is set in NSI, /S is redundant but explicit)
            if "${RUN_CMD[@]}" /S >/dev/null 2>&1; then
                pass "E2E install: installer ran without error"
            else
                fail "E2E install: installer returned non-zero"
            fi

            # Resolve the install directory. NSIS $TEMP expands differently on Wine vs. native.
            if $IS_WINDOWS; then
                # Git Bash $TEMP already maps to the Windows TEMP dir.
                E2E_INSTALL_DIR="${TEMP:-/tmp}/NsisE2ETest"
            else
                # Wine: NSIS $TEMP resolves inside the Wine prefix, not the host $TEMP.
                _wine_temp=$(wine cmd /c 'echo %TEMP%' 2>/dev/null | tr -d '\r\n')
                if command -v winepath &>/dev/null && [ -n "$_wine_temp" ]; then
                    E2E_INSTALL_DIR=$(winepath -u "${_wine_temp}\\NsisE2ETest" 2>/dev/null \
                        || echo "${HOME}/.wine/drive_c/users/$(id -un)/Temp/NsisE2ETest")
                else
                    E2E_INSTALL_DIR="${HOME}/.wine/drive_c/users/$(id -un)/Temp/NsisE2ETest"
                fi
            fi

            if [ -f "$E2E_INSTALL_DIR/INSTALLED.txt" ]; then
                pass "E2E install: INSTALLED.txt created"
            else
                fail "E2E install: INSTALLED.txt not found at $E2E_INSTALL_DIR"
            fi

            UNINSTALLER="$E2E_INSTALL_DIR/Uninstall.exe"
            if [ -f "$UNINSTALLER" ]; then
                if $IS_WINDOWS; then
                    "$UNINSTALLER" /S >/dev/null 2>&1 || true
                else
                    wine "$UNINSTALLER" /S >/dev/null 2>&1 || true
                fi
                # NSIS uninstallers on Windows copy themselves to TEMP before running;
                # give the cleanup process a moment to finish.
                sleep 2

                if [ -f "$E2E_INSTALL_DIR/INSTALLED.txt" ]; then
                    fail "E2E uninstall: INSTALLED.txt still present after uninstall"
                else
                    pass "E2E uninstall: INSTALLED.txt removed"
                fi

                if [ -d "$E2E_INSTALL_DIR" ]; then
                    fail "E2E uninstall: install directory still present after uninstall"
                else
                    pass "E2E uninstall: install directory removed"
                fi
            else
                fail "E2E uninstall: Uninstall.exe not found at $E2E_INSTALL_DIR"
            fi
        else
            skip "E2E run: requires Windows or Linux+Wine (not available on this platform)"
        fi
    fi
fi

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "═══════════════════════════════════════════════════════════════"
printf "  Results: %d passed, %d skipped, %d failed\n" "$PASS" "$SKIP" "$FAIL"
echo "═══════════════════════════════════════════════════════════════"
echo ""

[ "$FAIL" -eq 0 ]
