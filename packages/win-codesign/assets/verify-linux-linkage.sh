#!/usr/bin/env bash
# Fails unless every ELF file passed in only needs base-system libraries (glibc, libz) or
# libraries that ship in the bundle's lib/ directory. Guards against the Linux bundle
# depending on distro libraries again (the 1.3.x bundles needed libcrypto.so.1.1 and
# libcurl.so.4 from the build image, which Ubuntu 22.04+ no longer has).
#
#   - each DT_NEEDED entry must be a base-system library or exist as <lib-dir>/<name>
#   - DT_RUNPATH / DT_RPATH entries must be relative to the image ($ORIGIN)
#   - with --max-glibc, no GLIBC_x.y symbol version may be newer than <ver>
#
# Usage: verify-linux-linkage.sh [--lib-dir <bundle lib dir>] [--max-glibc <ver>] <elf> [<elf> ...]
set -euo pipefail

LIB_DIR=""
MAX_GLIBC=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --lib-dir)   LIB_DIR="$2";   shift 2 ;;
        --max-glibc) MAX_GLIBC="$2"; shift 2 ;;
        *)           break ;;
    esac
done

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 [--lib-dir <dir>] [--max-glibc <ver>] <elf> [<elf> ...]" >&2
    exit 2
fi

# Libraries every glibc-based distro provides (glibc itself, the dynamic loader, libz).
system_lib_regex='^(libc\.so\.6|libm\.so\.6|libdl\.so\.2|libpthread\.so\.0|librt\.so\.1|libresolv\.so\.2|libutil\.so\.1|libz\.so\.1|libgcc_s\.so\.1|ld-linux(-[a-z0-9_-]+)?\.so\.[0-9]+)$'

# Prints 0 when version $1 <= $2.
version_le() {
    awk -v a="$1" -v b="$2" 'BEGIN{n=split(a,A,"."); m=split(b,B,"."); k=(n>m?n:m);
        for(i=1;i<=k;i++){x=A[i]+0; y=B[i]+0; if(x<y){print 0; exit} if(x>y){print 1; exit}} print 0}'
}

status=0
for bin in "$@"; do
    if [[ ! -f "$bin" ]]; then
        echo "❌ Not found: $bin" >&2
        status=1
        continue
    fi
    if ! dyn="$(LC_ALL=C readelf -d "$bin" 2>/dev/null)" || [[ -z "$dyn" ]]; then
        echo "❌ $bin has no dynamic section (not a dynamically linked ELF file?)" >&2
        status=1
        continue
    fi
    echo "🔎 Needed libraries of $bin:"
    needed="$(awk -F'[][]' '/\(NEEDED\)/{print $2}' <<< "$dyn")"
    while IFS= read -r dep; do
        [[ -z "$dep" ]] && continue
        if [[ "$dep" =~ $system_lib_regex ]]; then
            echo "  ✅ $dep (base system)"
        elif [[ -n "$LIB_DIR" && -f "$LIB_DIR/$dep" ]]; then
            echo "  ✅ $dep (bundled)"
        else
            echo "  ❌ $dep (not a base-system library and not in bundled lib dir ${LIB_DIR:-<none>})" >&2
            status=1
        fi
    done <<< "$needed"

    rpaths="$(awk -F'[][]' '/\((RUNPATH|RPATH)\)/{print $2}' <<< "$dyn" | tr ':' '\n')"
    while IFS= read -r rp; do
        [[ -z "$rp" ]] && continue
        case "$rp" in
            '$ORIGIN'*) echo "  ✅ RUNPATH $rp" ;;
            *) echo "  ❌ RUNPATH $rp (absolute search path)" >&2; status=1 ;;
        esac
    done <<< "$rpaths"

    if [[ -n "$MAX_GLIBC" ]]; then
        newest="$(LC_ALL=C readelf -V "$bin" 2>/dev/null | grep -o 'GLIBC_[0-9][0-9.]*' | sed 's/GLIBC_//' | sort -t. -k1,1n -k2,2n -k3,3n | tail -n1)"
        if [[ -z "$newest" ]]; then
            echo "  ✅ no GLIBC symbol versions"
        elif [[ "$(version_le "$newest" "$MAX_GLIBC")" == 0 ]]; then
            echo "  ✅ needs GLIBC_$newest (<= $MAX_GLIBC)"
        else
            echo "  ❌ needs GLIBC_$newest, newer than $MAX_GLIBC" >&2
            status=1
        fi
    fi
done

if [[ $status -ne 0 ]]; then
    echo "❌ Libraries outside the base system and the bundle, absolute search paths or a too-new glibc found (see above)." >&2
fi
exit $status
