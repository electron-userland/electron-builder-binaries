#!/usr/bin/env bash
# Smoke test of an extracted archive toolset: with its bin/ first on PATH (as electron-builder runs fpm), the published
# fpm toolset builds deb (xz), pacman, freebsd and, where the toolset ships rpm, xzmt rpm packages; lzip round-trips.
# Usage: smoke-test.sh <archive toolset dir> <fpm toolset dir>
set -euo pipefail
trap 'echo "❌ smoke test failed at line $LINENO"' ERR

BUNDLE=$(cd "$1" && pwd)
FPM="$(cd "$2" && pwd)/fpm"
export PATH="$BUNDLE/bin:$PATH"
cd "$(mktemp -d)"

for t in xz lzip tar gtar ar gar bsdtar; do
    [ "$(command -v "$t")" = "$BUNDLE/bin/$t" ]
    "$t" --version | sed -n 1p
done
tar --version | grep 'GNU tar' >/dev/null
ar --version | grep 'GNU ar' >/dev/null
# fpm's ar_cmd wants `ar -qc` to write deterministic archives
: >empty
ar -qc probe.a empty
TZ=UTC LC_ALL=C ar -tv probe.a | grep '0/0.*1970' >/dev/null

mkdir -p root/opt/smoke
echo hello >root/opt/smoke/hello.txt
FPM_ARGS=(-s dir -n smoke -v 1.0.0 -C root)

"$FPM" "${FPM_ARGS[@]}" -t deb -a all --deb-compression xz -p smoke.deb .
[ "$(ar t smoke.deb | tr '\n' ' ')" = "debian-binary control.tar.xz data.tar.xz " ]
ar p smoke.deb data.tar.xz | xz -dc | tar -tf - | grep opt/smoke/hello.txt >/dev/null

# pacman's .MTREE is written by bsdtar: gzip, with sha256 digests
"$FPM" "${FPM_ARGS[@]}" -t pacman -a any --pacman-compression xz -p smoke.pkg.tar.xz .
tar -xJOf smoke.pkg.tar.xz .MTREE | gzip -dc | grep 'hello.txt.*sha256digest=' >/dev/null

# freebsd runs `tar --transform` (GNU tar)
"$FPM" "${FPM_ARGS[@]}" -t freebsd -a all -p smoke.txz .
tar -tJf smoke.txz | grep '+MANIFEST' >/dev/null

if [ -x "$BUNDLE/bin/rpmbuild" ]; then
    rpmbuild --version
    # pinned macros, and the user's ~/.rpmmacros is ignored
    printf '%%_rpmformat 6\n%%_build_id_links alldebug\n' >.rpmmacros
    [ "$(HOME=$PWD rpmbuild --eval '%{_rpmformat} %{_build_id_links}')" = "4 none" ]
    arch=$(uname -m)
    if [ "$arch" = arm64 ]; then arch=aarch64; fi
    "$FPM" "${FPM_ARGS[@]}" -t rpm --rpm-os linux -a "$arch" --rpm-compression xzmt -p smoke.rpm .
    # (stdout only: on macOS rpm also warns that it cannot lock the absent /var/lib/rpm keyring)
    [ "$(rpm -qp --qf '%{PAYLOADCOMPRESSOR} %{RPMFORMAT}' smoke.rpm 2>/dev/null)" = "xz 4" ]
    rpm -qlp smoke.rpm 2>/dev/null | grep /opt/smoke/hello.txt >/dev/null
fi

# electron-builder's tar.lz target
tar -cf smoke.tar root
lzip -9 -k smoke.tar
lzip -t smoke.tar.lz
lzip -dc smoke.tar.lz >out.tar
[ "$(cksum <out.tar)" = "$(cksum <smoke.tar)" ]
tar --lzip -tf smoke.tar.lz | grep opt/smoke/hello.txt >/dev/null

echo "✅ smoke test passed"
