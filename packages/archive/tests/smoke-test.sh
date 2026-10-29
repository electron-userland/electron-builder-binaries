#!/usr/bin/env bash
# Smoke test for an extracted archive toolset, the way electron-builder uses it: the toolset's bin/ first on PATH and
# no other xz, lzip, GNU tar, ar, bsdtar or rpm/rpmbuild reachable, the published fpm toolset builds deb (xz), pacman,
# freebsd and (where the toolset ships rpm) xzmt rpm packages, and lzip round-trips a tarball.
#
# Usage: smoke-test.sh --bundle-dir <archive toolset> --fpm-dir <fpm toolset> [--expect-rpm] [--remove-host-tools]
#                      [--host-rpm <path>]
#   --expect-rpm         the toolset must ship bin/rpm and bin/rpmbuild (otherwise it must not); also runs
#                        rpm-test.sh (host macro isolation, pinned macros)
#   --remove-host-tools  delete every other copy of those tools found on PATH (throwaway containers and CI runners
#                        only; uses sudo when needed; files the OS protects stay but are left off PATH)
#   --host-rpm           an independent rpm (e.g. the distro's rpm 4.x) that must read the rpm output; it is called
#                        by absolute path and is never on PATH
# Whatever --remove-host-tools does, the test runs with PATH = the toolset's bin/ + a directory of links to every
# other command on the original PATH except those tools.
# Portable bash (macOS bash 3.2).
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BUNDLE_DIR="" FPM_DIR="" EXPECT_RPM=0 REMOVE=0 HOST_RPM=""
while [ $# -gt 0 ]; do
    case "$1" in
        --bundle-dir) BUNDLE_DIR="$2"; shift 2 ;;
        --fpm-dir) FPM_DIR="$2"; shift 2 ;;
        --expect-rpm) EXPECT_RPM=1; shift ;;
        --remove-host-tools) REMOVE=1; shift ;;
        --host-rpm) HOST_RPM="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done
[ -d "$BUNDLE_DIR/bin" ] && [ -x "$FPM_DIR/fpm" ] || {
    echo "Usage: $0 --bundle-dir <archive toolset> --fpm-dir <fpm toolset> [--expect-rpm] [--remove-host-tools] [--host-rpm <path>]" >&2
    exit 2
}
BUNDLE_DIR=$(cd "$BUNDLE_DIR" && pwd -P)
FPM_DIR=$(cd "$FPM_DIR" && pwd -P)
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

WORK=$(mktemp -d "${TMPDIR:-/tmp}/archive-smoke.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

if [ "$OS" = "Linux" ]; then
    echo "━━ archive toolset smoke test on $(. /etc/os-release && echo "$PRETTY_NAME") ($(uname -m))"
    ldd --version 2>&1 | sed -n 1p | sed 's/^/   host /'
else
    echo "━━ archive toolset smoke test on macOS $(sw_vers -productVersion) ($(uname -m))"
fi
[ -f "$BUNDLE_DIR/VERSION.txt" ] && sed 's/^/   /' "$BUNDLE_DIR/VERSION.txt"
[ -f "$FPM_DIR/VERSION.txt" ] && sed 's/^/   fpm toolset: /' "$FPM_DIR/VERSION.txt"

# --- host isolation ----------------------------------------------------------------------------------------------
# Every command the toolset provides (and their usual siblings). `rpm` itself stays installed for --host-rpm.
HOST_TOOLS="xz unxz xzcat xzdec lzma unlzma lzcat lzmadec lzip lunzip plzip clzip pdlzip tarlz tar gtar gnutar ar gar bsdtar bsdcpio bsdcat rpmbuild rpmspec rpmsign"
OFF_PATH="$HOST_TOOLS rpm rpm2cpio rpm2archive"

echo "▶ Host tools"
OLD_IFS=$IFS
IFS=:
# shellcheck disable=SC2206 # split PATH on :
path_dirs=($PATH)
IFS=$OLD_IFS
if [ "$REMOVE" = "1" ]; then
    for d in "${path_dirs[@]}"; do
        [ -n "$d" ] && [ -d "$d" ] || continue
        for t in $HOST_TOOLS; do
            [ -e "$d/$t" ] || [ -L "$d/$t" ] || continue
            SUDO=""
            if [ ! -w "$d" ] && command -v sudo >/dev/null 2>&1; then SUDO=sudo; fi
            if $SUDO rm -f "$d/$t" 2>/dev/null && [ ! -e "$d/$t" ]; then
                echo "   removed $d/$t"
            else
                echo "   cannot remove $d/$t (protected by the OS); it stays off PATH"
            fi
        done
    done
fi
# PATH for the test: links to every other command on the original PATH (first one wins), minus OFF_PATH
HOSTBIN="$WORK/hostbin"
mkdir -p "$HOSTBIN"
for d in "${path_dirs[@]}"; do
    [ -n "$d" ] && [ -d "$d" ] || continue
    for f in "$d"/*; do
        name=$(basename "$f")
        [ -x "$f" ] && [ ! -d "$f" ] || continue
        [ ! -e "$HOSTBIN/$name" ] || continue
        skip=0
        for t in $OFF_PATH; do
            if [ "$name" = "$t" ]; then skip=1; fi
        done
        [ "$skip" = "1" ] || ln -s "$f" "$HOSTBIN/$name"
    done
done
export PATH="$BIN:$HOSTBIN"
hash -r
for t in $OFF_PATH; do
    found=$(type -ap "$t" 2>/dev/null | tr '\n' ' ' | sed 's/ $//' || true)
    if [ -z "$found" ] || [ "$found" = "$BIN/$t" ]; then
        :
    else
        ko "$t on PATH: $found"
    fi
done
ok "PATH reaches only the toolset's copy of: $OFF_PATH"

# --- the toolset's tools -----------------------------------------------------------------------------------------
echo "▶ Tools"
TOOLS="xz lzip tar gtar ar gar bsdtar"
if [ "$EXPECT_RPM" = "1" ]; then TOOLS="$TOOLS rpm rpmbuild"; fi
for t in $TOOLS; do
    expect_eq "$t resolves to the toolset" "$(command -v "$t" || true)" "$BIN/$t"
    if v=$("$t" --version 2>&1 | sed -n 1p) && [ -n "$v" ]; then ok "$t --version: $v"; else ko "$t --version failed: $v"; fi
done
if [ "$EXPECT_RPM" != "1" ]; then
    if [ -e "$BIN/rpm" ] || [ -e "$BIN/rpmbuild" ]; then ko "this toolset should not ship rpm"; else ok "no rpm in this toolset (as expected)"; fi
fi
identity() {
    if "$1" --version 2>&1 | sed -n 1p | grep "$2" >/dev/null; then ok "$1 is $2"; else ko "$1 is not $2"; fi
}
identity xz "XZ Utils"
identity lzip "lzip"
identity tar "GNU tar"
identity gtar "GNU tar"
identity ar "GNU ar"
identity gar "GNU ar"
identity bsdtar "bsdtar"

echo "▶ fpm's tool probes (FPM::Util#tar_cmd, #ar_cmd)"
(
    cd "$WORK"
    : >probe-empty
    for opt in --sort=name --mtime=@0; do tar "$opt" -cf probe.tar probe-empty || exit 1; done
) >"$WORK/probe.log" 2>&1 && ok "tar takes --sort=name and --mtime=@0 (tar_cmd picks tar)" || ko "tar rejects --sort/--mtime: $(cat "$WORK/probe.log")"
(
    cd "$WORK"
    rm -f probe.a
    ar -qc probe.a probe-empty && env TZ=UTC LANG=C LC_TIME=C ar -tv probe.a | grep '0/0.*1970'
) >"$WORK/probe.log" 2>&1 && ok "ar -qc is deterministic (ar_cmd picks ar -qc)" || ko "ar -qc is not deterministic: $(cat "$WORK/probe.log")"

# --- fpm -----------------------------------------------------------------------------------------------------------
mkdir -p "$WORK/root/opt/ebsmoke"
echo "hello from the archive toolset smoke test" >"$WORK/root/opt/ebsmoke/hello.txt"
head -c 200000 "$BIN/tar" >"$WORK/root/opt/ebsmoke/blob.bin"
FPM="$FPM_DIR/fpm"
FPM_ARGS=(-s dir -n ebsmoke -v 1.0.0 -C "$WORK/root")

echo "▶ deb (xz)"
DEB="$WORK/ebsmoke.deb"
run "fpm -t deb --deb-compression xz" "$WORK/deb.log" "$FPM" "${FPM_ARGS[@]}" -t deb -a all --deb-compression xz -p "$DEB" .
if [ -f "$DEB" ]; then
    members=$(ar t "$DEB" 2>&1 | tr '\n' ' ' | sed 's/ $//' || true)
    expect_eq "ar t (bundled GNU ar)" "$members" "debian-binary control.tar.xz data.tar.xz"
    if ar p "$DEB" data.tar.xz | xz -dc | tar -tf - | grep 'opt/ebsmoke/hello.txt' >/dev/null; then ok "data.tar.xz extracts (ar p | xz -dc | tar)"; else ko "data.tar.xz unreadable"; fi
    mkdir -p "$WORK/deb-x"
    if (cd "$WORK/deb-x" && ar x "$DEB" && tar -xJf data.tar.xz) && cmp -s "$WORK/deb-x/opt/ebsmoke/blob.bin" "$WORK/root/opt/ebsmoke/blob.bin"; then
        ok "deb payload round-trips (ar x, tar -xJf)"
    else
        ko "deb payload differs after extraction"
    fi
fi

echo "▶ pacman (xz)"
PKG="$WORK/ebsmoke-1.0.0-1-any.pkg.tar.xz"
run "fpm -t pacman --pacman-compression xz" "$WORK/pacman.log" "$FPM" "${FPM_ARGS[@]}" -t pacman -a any --pacman-compression xz -p "$PKG" .
if [ -f "$PKG" ]; then
    if xz -t "$PKG"; then ok "pacman package is valid xz"; else ko "pacman package is not valid xz"; fi
    entries=$(xz -dc "$PKG" | tar -tf - 2>&1 || true)
    for e in .PKGINFO .MTREE opt/ebsmoke/hello.txt; do
        if echo "$entries" | grep -x "\(\./\)\{0,1\}$e" >/dev/null; then ok "pacman package has $e"; else ko "pacman package has no $e: $(echo "$entries" | tr '\n' ' ')"; fi
    done
    # .MTREE is written by bsdtar: gzip, with sha256 digests
    if xz -dc "$PKG" | tar -xOf - .MTREE 2>/dev/null | gzip -dc 2>/dev/null | grep 'hello.txt.*sha256digest=' >/dev/null; then
        ok ".MTREE (bsdtar) has sha256 digests"
    else
        ko ".MTREE has no sha256 digests"
    fi
fi

echo "▶ freebsd (txz)"
TXZ="$WORK/ebsmoke-1.0.0.txz"
run "fpm -t freebsd" "$WORK/freebsd.log" "$FPM" "${FPM_ARGS[@]}" -t freebsd -a all -p "$TXZ" .
if [ -f "$TXZ" ]; then
    if xz -t "$TXZ" && xz -dc "$TXZ" | tar -tf - 2>/dev/null | grep '+MANIFEST' >/dev/null; then ok "txz is valid xz with a +MANIFEST"; else ko "txz unreadable"; fi
    if xz -dc "$TXZ" | tar -tf - 2>/dev/null | grep 'opt/ebsmoke/hello.txt$' >/dev/null; then ok "txz has the payload"; else ko "txz payload paths: $(xz -dc "$TXZ" | tar -tf - 2>&1 | tr '\n' ' ')"; fi
fi

if [ "$EXPECT_RPM" = "1" ]; then
    echo "▶ rpm (xzmt)"
    case "$(uname -m)" in arm64 | aarch64) RPM_ARCH=aarch64 ;; *) RPM_ARCH=x86_64 ;; esac
    RPM="$WORK/ebsmoke-1.0.0-1.$RPM_ARCH.rpm"
    run "fpm -t rpm --rpm-compression xzmt" "$WORK/rpm.log" "$FPM" "${FPM_ARGS[@]}" -t rpm --rpm-os linux -a "$RPM_ARCH" --rpm-compression xzmt -p "$RPM" .
    if [ -f "$RPM" ]; then
        expect_eq "rpm payload compressor" "$(rpm -qp --qf '%{PAYLOADCOMPRESSOR}' "$RPM" 2>&1)" "xz"
        expect_eq "RPMFORMAT" "$(rpm -qp --qf '%{RPMFORMAT}' "$RPM" 2>&1)" "4"
        if rpm -qlp "$RPM" 2>/dev/null | grep '/opt/ebsmoke/hello.txt' >/dev/null; then ok "rpm payload present"; else ko "rpm payload missing"; fi
    fi
fi

# --- lzip (electron-builder's tar.lz target) ------------------------------------------------------------------------
echo "▶ lzip round trip"
(
    cd "$WORK"
    tar -cf lz.tar -C root opt
    lzip -9 -k lz.tar
    lzip -t lz.tar.lz
    lzip -dc lz.tar.lz | cmp - lz.tar
    tar --lzip -tf lz.tar.lz | grep 'opt/ebsmoke/blob.bin'
    mkdir -p lz-x
    tar --lzip -xf lz.tar.lz -C lz-x
    cmp lz-x/opt/ebsmoke/blob.bin root/opt/ebsmoke/blob.bin
) >"$WORK/lzip.log" 2>&1 && ok "tar | lzip -9, lzip -t, lzip -d and tar --lzip -x round-trip" || { ko "lzip round trip"; sed 's/^/     /' "$WORK/lzip.log"; }

if [ "$EXPECT_RPM" = "1" ]; then
    echo "▶ rpm host isolation and pinned macros (rpm-test.sh)"
    rpm_args=(--bundle-dir "$BUNDLE_DIR" --fpm "$FPM" --plant-host-macros)
    if [ -n "$HOST_RPM" ]; then rpm_args+=(--host-rpm "$HOST_RPM"); fi
    if bash "$HERE/rpm-test.sh" "${rpm_args[@]}" >"$WORK/rpm-test.log" 2>&1; then
        ok "rpm-test.sh: $(tail -n 1 "$WORK/rpm-test.log")"
    else
        ko "rpm-test.sh"
        sed 's/^/     /' "$WORK/rpm-test.log"
    fi
fi

echo "━━ $pass passed, $fail failed"
[ "$fail" = "0" ]
