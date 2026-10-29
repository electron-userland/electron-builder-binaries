#!/usr/bin/env bash
# Smoke test for an extracted fpm toolset: with the bundle's bin/ first on PATH and no other xz anywhere on PATH,
# fpm builds xz-compressed deb, freebsd and pacman packages with the bundled xz, and (where the bundle ships rpm)
# an xzmt-compressed rpm with the bundled rpmbuild.
#
# Usage: smoke-test.sh --bundle-dir <dir> [--expect-rpm] [--remove-host-xz]
#   --expect-rpm      the bundle must ship bin/rpm and bin/rpmbuild (otherwise it must not)
#   --remove-host-xz  delete every other xz found on PATH (throwaway containers and CI runners only; uses sudo when
#                     needed). Without it, PATH entries that hold another xz are dropped instead.
# Needs ar (binutils, or Xcode's on macOS) for the deb target, GNU tar (as tar or gtar) for freebsd and pacman, and
# bsdtar for pacman (skipped without it).
set -euo pipefail

BUNDLE_DIR="" EXPECT_RPM=0 REMOVE_HOST_XZ=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --bundle-dir) BUNDLE_DIR="$2"; shift 2 ;;
        --expect-rpm) EXPECT_RPM=1; shift ;;
        --remove-host-xz) REMOVE_HOST_XZ=1; shift ;;
        *) echo "Unknown argument: $1"; exit 2 ;;
    esac
done
[[ -x "$BUNDLE_DIR/fpm" ]] || { echo "Usage: $0 --bundle-dir <extracted fpm toolset> [--expect-rpm] [--remove-host-xz]"; exit 2; }
BUNDLE_DIR=$(cd "$BUNDLE_DIR" && pwd)
BIN="$BUNDLE_DIR/bin"
OS=$(uname -s)

pass=0 fail=0
ok() { echo "  ✅ $1"; pass=$((pass + 1)); }
ko() { echo "  ❌ $1"; fail=$((fail + 1)); }
expect_eq() { if [ "$2" = "$3" ]; then ok "$1 = '$3'"; else ko "$1: expected '$3', got '$2'"; fi; }
# run <description> <log> <command...>: ok/ko on the exit status, printing the log on failure
run() {
    local desc="$1" log="$2"
    shift 2
    if "$@" >"$log" 2>&1; then ok "$desc"; else ko "$desc"; sed 's/^/     /' "$log"; fi
}

WORK=$(mktemp -d "${TMPDIR:-/tmp}/fpm-smoke.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

echo "━━ fpm toolset smoke test on $( (. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME") || echo "macOS $(sw_vers -productVersion)") ($(uname -m))"
if [ "$OS" = "Linux" ]; then ldd --version 2>&1 | sed -n 1p | sed 's/^/   host /'; fi
[ -f "$BUNDLE_DIR/VERSION.txt" ] && sed 's/^/   /' "$BUNDLE_DIR/VERSION.txt"

echo "▶ Host xz"
IFS=: read -r -a path_dirs <<<"$PATH"
kept=()
SUDO=""
for d in "${path_dirs[@]}"; do
    [ -n "$d" ] || continue
    if [ -e "$d/xz" ] || [ -L "$d/xz" ]; then
        if [ "$REMOVE_HOST_XZ" = "1" ]; then
            if [ ! -w "$d" ] && command -v sudo >/dev/null 2>&1; then SUDO=sudo; else SUDO=""; fi
            echo "   removing $d/xz"
            $SUDO rm -f "$d/xz"
        else
            echo "   dropping $d from PATH (it holds $d/xz)"
            continue
        fi
    fi
    kept+=("$d")
done
HOST_PATH=$(IFS=:; echo "${kept[*]}")
export PATH="$HOST_PATH"
hash -r
if command -v xz >/dev/null 2>&1; then ko "an xz is still on PATH: $(command -v xz)"; else ok "no xz on PATH"; fi

# fpm's freebsd target runs `tar --transform` (GNU tar). macOS's tar is bsdtar: put GNU tar first as `tar`
# (electron-builder provides gtar through the linux-tools-mac toolset).
if ! tar --version 2>/dev/null | grep 'GNU tar' >/dev/null; then
    if command -v gtar >/dev/null 2>&1; then
        mkdir -p "$WORK/gnutar"
        ln -s "$(command -v gtar)" "$WORK/gnutar/tar"
        PATH="$WORK/gnutar:$PATH"
        echo "   tar -> $(command -v gtar) (GNU tar, for fpm's freebsd target)"
    else
        echo "   ⚠️ no GNU tar found; fpm's freebsd target needs it"
    fi
fi

export PATH="$BIN:$PATH"
hash -r

echo "▶ Bundled tools"
expect_eq "xz resolves to the bundle" "$(command -v xz)" "$BIN/xz"
expect_eq "xz on PATH" "$(type -ap xz | tr '\n' ' ' | sed 's/ $//')" "$BIN/xz"
if v=$(xz --version 2>&1); then ok "xz --version: $(echo "$v" | tr '\n' ' ')"; else ko "xz --version failed: $v"; fi
if [ "$EXPECT_RPM" = "1" ]; then
    expect_eq "rpmbuild resolves to the bundle" "$(command -v rpmbuild || true)" "$BIN/rpmbuild"
    if v=$(rpmbuild --version 2>&1); then ok "rpmbuild --version: $v"; else ko "rpmbuild --version failed: $v"; fi
else
    if [ -e "$BIN/rpmbuild" ] || [ -e "$BIN/rpm" ]; then ko "this bundle should not ship rpm"; else ok "no rpm in this bundle (as expected)"; fi
fi

mkdir -p "$WORK/root/opt/ebsmoke"
echo "hello from the fpm toolset smoke test" >"$WORK/root/opt/ebsmoke/hello.txt"
FPM=("$BUNDLE_DIR/fpm" -s dir -n ebsmoke -v 1.0.0 -C "$WORK/root")

echo "▶ deb (xz)"
DEB="$WORK/ebsmoke.deb"
run "fpm -t deb --deb-compression xz" "$WORK/deb.log" "${FPM[@]}" -t deb -a all --deb-compression xz -p "$DEB" .
if [ -f "$DEB" ]; then
    if ar t "$DEB" | grep -x 'data.tar.xz' >/dev/null; then ok "deb has data.tar.xz"; else ko "deb has no data.tar.xz: $(ar t "$DEB" | tr '\n' ' ')"; fi
    if ar p "$DEB" data.tar.xz | xz -dc | tar -tf - | grep 'opt/ebsmoke/hello.txt' >/dev/null; then ok "deb payload decompresses with the bundled xz"; else ko "deb payload unreadable"; fi
fi

echo "▶ freebsd (txz)"
TXZ="$WORK/ebsmoke.txz"
run "fpm -t freebsd" "$WORK/freebsd.log" "${FPM[@]}" -t freebsd -a all -p "$TXZ" .
if [ -f "$TXZ" ]; then
    if xz -t "$TXZ" && xz -dc "$TXZ" | tar -tf - 2>/dev/null | grep '+MANIFEST' >/dev/null; then ok "txz is valid xz with a +MANIFEST"; else ko "txz unreadable"; fi
fi

echo "▶ pacman (xz)"
# fpm's pacman target also runs bsdtar (for .MTREE)
if command -v bsdtar >/dev/null 2>&1; then
    PKG="$WORK/ebsmoke.pkg.tar.xz"
    run "fpm -t pacman --pacman-compression xz" "$WORK/pacman.log" "${FPM[@]}" -t pacman -a any --pacman-compression xz -p "$PKG" .
    if [ -f "$PKG" ]; then
        if xz -t "$PKG" && xz -dc "$PKG" | tar -tf - 2>/dev/null | grep '.PKGINFO' >/dev/null; then ok "pacman package is valid xz with a .PKGINFO"; else ko "pacman package unreadable"; fi
    fi
else
    echo "   skipped: fpm's pacman target needs bsdtar, which is not installed"
fi

if [ "$EXPECT_RPM" = "1" ]; then
    echo "▶ rpm (xzmt)"
    case "$(uname -m)" in arm64 | aarch64) RPM_ARCH=aarch64 ;; *) RPM_ARCH=x86_64 ;; esac
    RPM="$WORK/ebsmoke-1.0.0-1.$RPM_ARCH.rpm"
    run "fpm -t rpm --rpm-compression xzmt" "$WORK/rpm.log" "${FPM[@]}" -t rpm --rpm-os linux -a "$RPM_ARCH" --rpm-compression xzmt -p "$RPM" .
    if [ -f "$RPM" ]; then
        expect_eq "rpm payload compressor" "$(rpm -qp --qf '%{PAYLOADCOMPRESSOR}' "$RPM")" "xz"
        if rpm -qlp "$RPM" | grep '/opt/ebsmoke/hello.txt' >/dev/null; then ok "rpm payload present"; else ko "rpm payload missing"; fi
        expect_eq "RPMFORMAT" "$(rpm -qp --qf '%{RPMFORMAT}' "$RPM")" "4"
    fi
fi

echo "━━ $pass passed, $fail failed"
[ "$fail" = "0" ]
