#!/usr/bin/env bash
# Self-test for scripts/verify-licenses.sh: builds tiny bundles whose "binaries" are just magic bytes and checks the
# guard accepts and rejects the right ones. Every case runs twice: with bash reading the magic bytes, and with od
# (the fallback). Portable bash: runs on Linux, macOS (bash 3.2) and Git Bash on Windows.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFY="$HERE/../verify-licenses.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/verify-licenses-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# --- Fixtures: magic bytes plus a little padding ---
elf()       { mkdir -p "$(dirname "$1")"; printf '\177ELF\002\001\001\000padding' > "$1"; }
macho()     { mkdir -p "$(dirname "$1")"; printf '\317\372\355\376\007\000\000\001padding' > "$1"; }
macho32be() { mkdir -p "$(dirname "$1")"; printf '\376\355\372\316\000\000\000\022padding' > "$1"; }
fat()       { mkdir -p "$(dirname "$1")"; printf '\312\376\272\276\000\000\000\002padding' > "$1"; }
pe()        { mkdir -p "$(dirname "$1")"; printf 'MZ\220\000\003\000\000\000padding' > "$1"; }
java()      { mkdir -p "$(dirname "$1")"; printf '\312\376\272\276\000\000\000\064padding' > "$1"; }
text()      { mkdir -p "$(dirname "$1")"; printf '%s\n' "${2:-#!/bin/sh}" > "$1"; }
license()   { mkdir -p "$1"; printf 'Permission is hereby granted, free of charge\n' > "$1/${2:-LICENSE}"; }
manifest()  { mkdir -p "$1/LICENSES"; printf '%b' "$2" > "$1/LICENSES/MANIFEST.tsv"; }
exempt()    { mkdir -p "$1/LICENSES"; printf '%b' "$2" > "$1/LICENSES/EXEMPT.tsv"; }

# new_bundle <name>: a bundle with one binary of every kind, all licensed, plus non-binaries that look close
new_bundle() {
    local d="$WORK/$MODE/$1"
    rm -rf "$d"
    elf "$d/linux/bin/tool"
    macho "$d/mac/bin/tool"
    fat "$d/mac/lib/libuniversal.dylib"
    pe "$d/win/tool.exe"
    pe "$d/win/helper lib.dll"
    java "$d/share/Main.class"
    text "$d/linux/bin/wrapper.sh"
    text "$d/README.md" $'Notes\nMZ starting a later line does not make a binary\n\177ELF neither'
    printf 'ZM\000\000' > "$d/not-mz"
    : > "$d/empty"
    printf 'M' > "$d/one-byte"
    manifest "$d" "# path\tcomponent\n\nlinux/bin/tool\ttool\nmac/bin/tool\ttool\n./mac/lib/libuniversal.dylib\tuniversal\nwin/tool.exe\ttool\nwin/helper lib.dll\thelper\nwin/helper lib.dll\tzlib\n"
    license "$d/LICENSES/tool" COPYING
    license "$d/LICENSES/universal"
    license "$d/LICENSES/helper" "LICENSE.txt"
    license "$d/LICENSES/zlib/sub/dir"
    echo "$d"
}

failures=0
# expect <pass|fail> <description> <bundle> [grep -E pattern the output must match...]
expect() {
    local want="$1" desc="$2" bundle="$3" out rc=0 got pattern
    shift 3
    out="$(VERIFY_LICENSES_FORCE_OD="$FORCE_OD" bash "$VERIFY" "$bundle" 2>&1)" || rc=$?
    got=pass
    [ "$rc" -eq 0 ] || got=fail
    if [ "$got" != "$want" ]; then
        echo "❌ [$MODE] $desc: expected $want, got $got (exit $rc)"
        printf '%s\n' "$out" | sed 's/^/     /'
        failures=$((failures + 1))
        return 0
    fi
    for pattern in ${1+"$@"}; do
        if ! printf '%s\n' "$out" | grep -qE -- "$pattern"; then
            echo "❌ [$MODE] $desc: output does not match /$pattern/"
            printf '%s\n' "$out" | sed 's/^/     /'
            failures=$((failures + 1))
            return 0
        fi
    done
    echo "✓ [$MODE] $desc"
}

for MODE in bash od; do
    FORCE_OD=0
    [ "$MODE" = bash ] || FORCE_OD=1

    # 1. Detection: exactly the magic-byte binaries, whatever their names.
    B="$(new_bundle detect)"
    listed="$(VERIFY_LICENSES_FORCE_OD="$FORCE_OD" bash "$VERIFY" --list "$B")"
    expected="$(printf '%s\n' "linux/bin/tool" "mac/bin/tool" "mac/lib/libuniversal.dylib" "win/helper lib.dll" "win/tool.exe")"
    if [ "$listed" = "$expected" ]; then
        echo "✓ [$MODE] --list finds ELF, Mach-O, fat Mach-O and PE files, not Java classes, scripts or text"
    else
        echo "❌ [$MODE] --list: expected"; printf '%s\n' "$expected" | sed 's/^/     /'
        echo "   got"; printf '%s\n' "$listed" | sed 's/^/     /'
        failures=$((failures + 1))
    fi
    macho32be "$B/mac/bin/old"
    printf '\276\272\376\312\000\000\000\002' > "$B/mac/bin/fat-swapped"
    printf '\312\376\272\277\000\000\000\002' > "$B/mac/bin/fat64"
    elf "$B/no extension"
    listed="$(VERIFY_LICENSES_FORCE_OD="$FORCE_OD" bash "$VERIFY" --list "$B" | grep -cE '^(mac/bin/(old|fat-swapped|fat64)|no extension)$' || true)"
    if [ "$listed" = 4 ]; then
        echo "✓ [$MODE] --list finds 32-bit, byte-swapped and 64-bit fat Mach-O, and binaries without extensions"
    else
        echo "❌ [$MODE] --list found $listed of the 4 other Mach-O / extensionless binaries"
        failures=$((failures + 1))
    fi

    # 2. A fully licensed bundle passes.
    B="$(new_bundle ok)"
    expect pass "licensed bundle passes" "$B" "All 5 binaries have license files \(0 exempted"

    # 3. Unlisted binaries fail, each one named.
    B="$(new_bundle unlisted)"
    elf "$B/linux/lib/libextra.so.1"
    pe "$B/win/plugins/extra.dll"
    expect fail "unlisted binaries fail" "$B" \
        "linux/lib/libextra\.so\.1: elf binary not listed" "win/plugins/extra\.dll: pe binary not listed" "2 problem\\(s\\)"

    # 4. A component without license files fails: no directory, or only empty files.
    B="$(new_bundle nolicense)"
    rm -rf "$B/LICENSES/universal"
    : > "$B/LICENSES/helper/LICENSE.txt"
    expect fail "components without license files fail" "$B" \
        "LICENSES/universal/: missing" "LICENSES/helper/: has no non-empty license file"

    # 5. A manifest path that does not exist fails.
    B="$(new_bundle stale)"
    printf 'win/gone.exe\ttool\n' >> "$B/LICENSES/MANIFEST.tsv"
    expect fail "manifest path not in the bundle fails" "$B" "win/gone\.exe: listed in LICENSES/MANIFEST\.tsv \(tool\) but not in the bundle"

    # 6. No MANIFEST.tsv: fails when there are binaries, passes when there are none.
    B="$(new_bundle nomanifest)"
    rm "$B/LICENSES/MANIFEST.tsv"
    expect fail "missing MANIFEST.tsv fails" "$B" "MANIFEST\.tsv is missing \(5 binaries" "linux/bin/tool: elf binary not listed"
    mkdir -p "$WORK/$MODE/nobinaries"
    text "$WORK/$MODE/nobinaries/run.sh"
    expect pass "bundle without binaries passes without a manifest" "$WORK/$MODE/nobinaries" "All 0 binaries"

    # 7. Globs cover many binaries; a glob matching no binary fails.
    B="$(new_bundle glob)"
    elf "$B/linux/lib/liba.so"
    elf "$B/linux/lib/deep/libb.so.2"
    printf 'linux/lib/*.so*\tlibs\n' >> "$B/LICENSES/MANIFEST.tsv"
    license "$B/LICENSES/libs"
    expect pass "glob entry covers binaries in subdirectories" "$B" "All 7 binaries"
    printf 'linux/plugins/*.so\tlibs\n' >> "$B/LICENSES/MANIFEST.tsv"
    expect fail "glob entry matching no binary fails" "$B" "linux/plugins/\*\.so: listed in LICENSES/MANIFEST\.tsv \(libs\) but matches no binary"

    # 8. Exemptions: printed loudly; the binaries they cover pass; a reason is required.
    B="$(new_bundle exempt)"
    pe "$B/win/vendor/a.dll"
    pe "$B/win/vendor/b.dll"
    elf "$B/linux/bin/pending"
    exempt "$B" "# pending decision\nwin/vendor/*.dll\tUpstream ships no license file; asked upstream\nlinux/bin/pending\tLicense under review\n"
    expect pass "exempted binaries pass and are printed" "$B" \
        "LICENSE EXEMPTION: win/vendor/\*\.dll" "Reason: Upstream ships no license file" "      - win/vendor/a\.dll" \
        "      - win/vendor/b\.dll" "LICENSE EXEMPTION: linux/bin/pending" "\(3 exempted by LICENSES/EXEMPT\.tsv\)"
    out="$(GITHUB_ACTIONS=true VERIFY_LICENSES_FORCE_OD="$FORCE_OD" bash "$VERIFY" "$B" 2>&1)"
    if printf '%s\n' "$out" | grep -qF '::warning title=License exemption::win/vendor/*.dll: Upstream ships no license file; asked upstream (2 binaries without license files)'; then
        echo "✓ [$MODE] exemptions are raised as GitHub Actions warnings"
    else
        echo "❌ [$MODE] no GitHub Actions warning for the exemption"; printf '%s\n' "$out" | sed 's/^/     /'
        failures=$((failures + 1))
    fi
    printf 'linux/bin/old-thing\tNo longer shipped\n' >> "$B/LICENSES/EXEMPT.tsv"
    expect pass "an exemption matching nothing is reported, not fatal" "$B" "Matches no unlisted binary"
    printf 'win/other.dll\n' >> "$B/LICENSES/EXEMPT.tsv"
    expect fail "an exemption without a reason fails" "$B" "LICENSES/EXEMPT\.tsv:5: expected"
    B="$(new_bundle exempt-partial)"
    pe "$B/win/vendor/a.dll"
    elf "$B/linux/bin/unexpected"
    exempt "$B" "win/vendor/*.dll\tpending\n"
    expect fail "an exemption covers only what it matches" "$B" "linux/bin/unexpected: elf binary not listed" "1 problem\\(s\\)"

    # 9. Malformed manifest lines fail.
    B="$(new_bundle malformed)"
    printf 'linux/bin/tool\n../outside\ttool\n/abs/path\ttool\nwin/tool.exe\tbad/name\n' >> "$B/LICENSES/MANIFEST.tsv"
    expect fail "malformed manifest lines fail" "$B" "MANIFEST\.tsv:9: expected" "\.\./outside: the path must be relative" \
        "/abs/path: the path must be relative" "bad/name: not a valid component"

    # 10. CRLF line endings (files edited on Windows) are accepted.
    B="$(new_bundle crlf)"
    awk '{printf "%s\r\n", $0}' "$B/LICENSES/MANIFEST.tsv" > "$B/LICENSES/MANIFEST.crlf"
    mv "$B/LICENSES/MANIFEST.crlf" "$B/LICENSES/MANIFEST.tsv"
    # Look for the CR with od: grep on Git Bash strips CRs from DOS-style text before matching.
    od -An -c "$B/LICENSES/MANIFEST.tsv" | grep -q '\\r' || { echo "❌ fixture: expected CRLF manifest"; exit 1; }
    expect pass "CRLF manifest passes" "$B" "All 5 binaries"

    # 11. Usage errors.
    rc=0; bash "$VERIFY" >/dev/null 2>&1 || rc=$?
    if [ "$rc" = 2 ]; then echo "✓ [$MODE] no argument exits 2"; else echo "❌ [$MODE] no argument exits $rc"; failures=$((failures + 1)); fi
    rc=0; bash "$VERIFY" "$WORK/does-not-exist" >/dev/null 2>&1 || rc=$?
    if [ "$rc" = 2 ]; then echo "✓ [$MODE] missing bundle exits 2"; else echo "❌ [$MODE] missing bundle exits $rc"; failures=$((failures + 1)); fi
done

echo ""
if [ "$failures" -gt 0 ]; then
    echo "❌ $failures verify-licenses test(s) failed"
    exit 1
fi
echo "✓ All verify-licenses tests passed"
