#!/usr/bin/env bash
# Smoke test for an extracted rpm toolset bundle.
#
# Usage: test.sh --bundle-dir <dir> [--fpm <fpm-executable>] [--plant-host-macros] [--host-rpm <path>]
#   --fpm                fpm entrypoint (e.g. the extracted fpm toolset's ./fpm). Default: `fpm` on PATH.
#   --plant-host-macros  write poisoned /etc/rpm/macros.zz-poison and ~/.rpmmacros (needs write access
#                        to /etc, uses sudo when available) and assert the bundle ignores them.
#   --host-rpm           an independent rpm binary (e.g. distro rpm 4.x) that must be able to read the output.
set -euo pipefail

BUNDLE_DIR="" FPM="fpm" PLANT=0 HOST_RPM=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --bundle-dir) BUNDLE_DIR="$2"; shift 2 ;;
        --fpm) FPM="$2"; shift 2 ;;
        --plant-host-macros) PLANT=1; shift ;;
        --host-rpm) HOST_RPM="$2"; shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done
[[ -d "$BUNDLE_DIR/bin" ]] || { echo "Usage: $0 --bundle-dir <extracted bundle>"; exit 1; }
BUNDLE_DIR=$(cd "$BUNDLE_DIR" && pwd)

pass=0 fail=0
ok() { echo "  ✅ $1"; pass=$((pass + 1)); }
ko() { echo "  ❌ $1"; fail=$((fail + 1)); }
expect_eq() { if [ "$2" = "$3" ]; then ok "$1 = '$3'"; else ko "$1: expected '$3', got '$2'"; fi; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export PATH="$BUNDLE_DIR/bin:$PATH"
OS=$(uname -s)

echo "━━ rpm toolset smoke test on $( (. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME") || sw_vers -productVersion) ($(uname -m))"
[ -f "$BUNDLE_DIR/VERSION.txt" ] && sed 's/^/   /' "$BUNDLE_DIR/VERSION.txt"
if [ "$OS" = "Linux" ]; then ldd --version 2>&1 | sed -n 1p | sed 's/^/   host /'; fi

echo "▶ Binaries"
expect_eq "rpmbuild resolves to bundle" "$(command -v rpmbuild)" "$BUNDLE_DIR/bin/rpmbuild"
if v=$(rpmbuild --version 2>&1); then ok "rpmbuild --version: $v"; else ko "rpmbuild --version failed: $v"; fi
if v=$(rpm --version 2>&1); then ok "rpm --version: $v"; else ko "rpm --version failed: $v"; fi
if [ "$OS" = "Linux" ]; then
    # fpm's portable ruby exports LD_LIBRARY_PATH; bundled libs must still win (DT_RPATH).
    mkdir -p "$WORK/badlibs"
    for l in libz.so.1 libpopt.so.0 liblzma.so.5; do : >"$WORK/badlibs/$l"; done
    if v=$(LD_LIBRARY_PATH="$WORK/badlibs" rpmbuild --version 2>&1); then ok "immune to hostile LD_LIBRARY_PATH"; else ko "LD_LIBRARY_PATH hijacks bundled libs: $v"; fi
fi

if [ "$PLANT" = "1" ]; then
    echo "▶ Planting host/user macros that must be ignored"
    if [ -e "$HOME/.rpmmacros" ] || [ -e "$HOME/.config/rpm" ] || [ -e /etc/rpm/macros.zz-poison ]; then
        echo "Refusing to overwrite existing ~/.rpmmacros, ~/.config/rpm or /etc/rpm/macros.zz-poison"; exit 1
    fi
    SUDO=""
    if [ ! -w /etc ] && command -v sudo >/dev/null 2>&1; then SUDO="sudo"; fi
    $SUDO mkdir -p /etc/rpm
    printf '%%_build_id_links alldebug\n%%_rpmformat 6\n%%eb_poison_etc 1\n' | $SUDO tee /etc/rpm/macros.zz-poison >/dev/null
    printf '%%_build_id_links alldebug\n%%_rpmformat 6\n%%eb_poison_home 1\n' >"$HOME/.rpmmacros"
    trap 'rm -rf "$WORK"; $SUDO rm -f /etc/rpm/macros.zz-poison; rm -rf "$HOME/.rpmmacros" "$HOME/.config/rpm"' EXIT
    # Positive control: the raw binary (no wrapper) does read them, so the assertions below are meaningful.
    raw() { RPM_CONFIGDIR="$BUNDLE_DIR/lib/rpm" MAGIC="$BUNDLE_DIR/share/misc/magic.mgc" "$BUNDLE_DIR/libexec/rpmbuild" "$@"; }
    expect_eq "control: unwrapped rpmbuild reads /etc/rpm + ~/.rpmmacros" "$(raw --eval '%{?eb_poison_etc}:%{?eb_poison_home}')" "1:1"
    expect_eq "$HOME/.rpmmacros ignored" "$(rpmbuild --eval '%{?eb_poison_home}')" ""
    # rpm >= 4.20 prefers $XDG_CONFIG_HOME/rpm/macros over ~/.rpmmacros when it exists.
    mkdir -p "$HOME/.config/rpm"
    printf '%%eb_poison_xdg 1\n' >"$HOME/.config/rpm/macros"
    expect_eq "control: unwrapped rpmbuild reads ~/.config/rpm/macros" "$(raw --eval '%{?eb_poison_xdg}')" "1"
    expect_eq "/etc/rpm/macros.* ignored" "$(rpmbuild --eval '%{?eb_poison_etc}')" ""
    expect_eq "$HOME/.config/rpm/macros ignored" "$(rpmbuild --eval '%{?eb_poison_xdg}')" ""
fi

echo "▶ Pinned macros"
expect_eq "%_rpmformat" "$(rpmbuild --eval '%{_rpmformat}')" "4"
expect_eq "%_build_id_links" "$(rpmbuild --eval '%{_build_id_links}')" "none"
expect_eq "%_rpmconfigdir" "$(rpmbuild --eval '%{_rpmconfigdir}')" "$BUNDLE_DIR/lib/rpm"
expect_eq "--define still overrides pins" "$(rpmbuild --define '_build_id_links compat' --eval '%{_build_id_links}')" "compat"

echo "▶ Building a package with fpm ($FPM)"
mkdir -p "$WORK/app"
HAS_BUILD_ID=0
if [ "$OS" = "Linux" ]; then
    # first real ELF executable (on coreutils-single systems such as EL8 images /bin/true is a script)
    for c in /bin/true /usr/bin/env /bin/bash; do
        if [ "$(head -c 4 "$c" | od -An -tx1 | tr -d ' \n')" = "7f454c46" ]; then cp -L "$c" "$WORK/app/hello"; break; fi
    done
    if command -v readelf >/dev/null 2>&1; then
        if readelf -n "$WORK/app/hello" | grep -q 'Build ID'; then HAS_BUILD_ID=1; ok "payload ELF has a GNU build-id"; else ko "payload ELF has no build-id; test would be meaningless"; fi
    else
        HAS_BUILD_ID=1 # distro coreutils are always built with --build-id; cannot inspect without binutils
    fi
else
    printf '#!/bin/sh\necho hello\n' >"$WORK/app/hello"
fi
chmod 755 "$WORK/app/hello"
case "$(uname -m)" in arm64 | aarch64) RPM_ARCH=aarch64 ;; *) RPM_ARCH=x86_64 ;; esac
[ "$OS" = "Darwin" ] && RPM_ARCH=x86_64
PKG="$WORK/ebtest-1.0.0-1.$RPM_ARCH.rpm"
if (cd "$WORK" && "$FPM" -s dir -t rpm --rpm-os linux -n ebtest -v 1.0.0 -a "$RPM_ARCH" -p "$PKG" app/=/opt/ebtest) >"$WORK/fpm.log" 2>&1; then
    ok "fpm produced $(basename "$PKG") ($(wc -c <"$PKG" | tr -d ' ') bytes)"
else
    ko "fpm failed"; cat "$WORK/fpm.log"
fi

if [ -f "$PKG" ]; then
    echo "▶ Inspecting output with bundled rpm"
    files=$(rpm -qlp "$PKG")
    while IFS= read -r line; do echo "     $line"; done <<<"$files"
    if echo "$files" | grep -q '/opt/ebtest/hello'; then ok "payload present"; else ko "payload missing"; fi
    if echo "$files" | grep -q '\.build-id'; then ko "/usr/lib/.build-id links present"; else ok "no /usr/lib/.build-id links$([ "$HAS_BUILD_ID" = 1 ] || echo ' (no ELF payload on this OS)')"; fi
    expect_eq "RPMVERSION (builder)" "$(rpm -qp --qf '%{RPMVERSION}' "$PKG")" "$(rpm --version | awk '{print $3}')"
    expect_eq "RPMFORMAT" "$(rpm -qp --qf '%{RPMFORMAT}' "$PKG")" "4"
    if [ "$PLANT" = "1" ]; then
        if rpm -qp --qf '[%{FILENAMES}\n]' "$PKG" | grep -q 'build-id'; then ko "planted %_build_id_links leaked into build"; else ok "planted %_build_id_links did not leak into build"; fi
    fi
    if [ -n "$HOST_RPM" ]; then
        echo "▶ Reading output with host $("$HOST_RPM" --version)"
        if out=$(env -u RPM_CONFIGDIR "$HOST_RPM" -qlp --nosignature "$PKG" 2>&1); then
            ok "host rpm reads package"
            if echo "$out" | grep -q '\.build-id'; then ko "host rpm sees .build-id links"; fi
        else
            ko "host rpm cannot read package: $out"
        fi
        if out=$(env -u RPM_CONFIGDIR "$HOST_RPM" -K --nosignature "$PKG" 2>&1); then ok "host rpm -K: $out"; else ko "host rpm -K failed: $out"; fi
    fi
fi

echo "━━ $pass passed, $fail failed"
[ "$fail" = "0" ]
