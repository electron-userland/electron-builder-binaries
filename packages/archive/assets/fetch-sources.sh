#!/usr/bin/env bash
# Downloads the upstream source tarballs of the archive toolset into <dir> and verifies each one: its sha256 must
# match the pin in constants.sh and, when upstream signs it, its OpenPGP signature must be good and made by one of
# the keys pinned for it (keys/<fingerprint>.asc, primary key fingerprint checked). Runs on the build host (it needs
# curl and gpg), so the build containers never fetch anything themselves.
#
# Usage: fetch-sources.sh <dir> [COMPONENT...]   (default: every component in ARCHIVE_COMPONENTS)
set -euo pipefail

ASSETS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=SCRIPTDIR/constants.sh
source "$ASSETS/constants.sh"

DEST="${1:?usage: fetch-sources.sh <dir> [COMPONENT...]}"
shift
COMPONENTS="${*:-$ARCHIVE_COMPONENTS}"
mkdir -p "$DEST"
DEST=$(cd "$DEST" && pwd)

CURL=(curl -fsSL --retry 5 --retry-delay 10 --max-time 600)
# --retry-all-errors (curl >= 7.71) also retries DNS failures and resets
if curl --help all 2>/dev/null | grep -- '--retry-all-errors' >/dev/null; then CURL+=(--retry-all-errors); fi

# verify_signature <file> <signature> <fingerprint...>
verify_signature() {
    local file="$1" sig="$2" home status fpr primary="" allowed=0 line
    shift 2
    command -v gpg >/dev/null 2>&1 || die "gpg is needed to verify $(basename "$file")"
    # short path: gpg's sockets must fit in sun_path on macOS
    home=$(mktemp -d /tmp/gpg.XXXXXX)
    chmod 700 "$home"
    for fpr in "$@"; do
        [ -s "$ASSETS/keys/$fpr.asc" ] || die "keys/$fpr.asc is missing"
        gpg --homedir "$home" --batch --quiet --import "$ASSETS/keys/$fpr.asc" 2>/dev/null
    done
    status=$(gpg --homedir "$home" --batch --status-fd 1 --verify "$sig" "$file" 2>"$home/stderr" || true)
    if echo "$status" | grep -E '^\[GNUPG:\] (BADSIG|ERRSIG|NO_PUBKEY)' >/dev/null; then
        sed 's/^/   /' "$home/stderr" >&2
        rm -rf "$home"
        die "$(basename "$file"): bad signature or signed by an unexpected key (allowed: $*)"
    fi
    line=$(echo "$status" | awk '$2 == "VALIDSIG"' | sed -n 1p)
    primary=$(echo "$line" | awk '{print $NF}')
    for fpr in "$@"; do
        if [ "$primary" = "$fpr" ]; then allowed=1; fi
    done
    if [ -z "$line" ] || [ "$allowed" != "1" ]; then
        sed 's/^/   /' "$home/stderr" >&2
        rm -rf "$home"
        die "$(basename "$file"): no valid signature from an allowed key (allowed: $*; got: ${primary:-none})"
    fi
    # an expired key still proves who signed; the sha256 pin is checked as well
    if echo "$status" | grep -E '^\[GNUPG:\] (EXPKEYSIG|KEYEXPIRED)' >/dev/null; then
        echo "  ⚠️  $(basename "$file"): signing key $primary has expired since"
    fi
    echo "  ✓ signature $(basename "$file"): $(grep -m1 -o '".*"' "$home/stderr" || true) key $primary, made $(echo "$line" | awk '{print $4}')"
    rm -rf "$home"
}

# download <output> <url>: retried, atomic
download() {
    rm -f "$1.part"
    if "${CURL[@]}" "$2" -o "$1.part"; then
        mv "$1.part" "$1"
    else
        rm -f "$1.part"
        return 1
    fi
}

for c in $COMPONENTS; do
    version=$(component_var "$c" VERSION)
    sha=$(component_var "$c" SHA256)
    urls=$(component_var "$c" URLS)
    sig=$(component_var "$c" SIG)
    keys=$(component_var "$c" KEYS)
    [ -n "$version" ] && [ -n "$sha" ] && [ -n "$urls" ] || die "$c: incomplete source pin in constants.sh"
    name=$(tarball_name "$c")
    out="$DEST/$name"
    echo "⬇️  $c $version ($name)"
    used=""
    if [ -f "$out" ] && [ "$(sha256_of "$out")" = "$sha" ]; then
        used="(cached)"
    else
        rm -f "$out"
        for url in $urls; do
            if download "$out" "$url"; then used="$url"; break; fi
            echo "   $url failed"
        done
        [ -n "$used" ] || die "could not download $name from: $urls"
        echo "   from $used"
    fi
    verify_sha256 "$out" "$sha"
    if [ -n "$sig" ]; then
        # keys is a space separated list
        # shellcheck disable=SC2086
        set -- $keys
        [ $# -gt 0 ] || die "$c: signed upstream but no keys pinned"
        if [ ! -s "$out$sig" ]; then
            got=0
            for url in $urls; do
                if download "$out$sig" "$url$sig"; then got=1; break; fi
                echo "   $url$sig failed"
            done
            [ "$got" = "1" ] || die "could not download the signature of $name"
        fi
        verify_signature "$out" "$out$sig" "$@"
    else
        echo "  - $c: upstream publishes no signature; sha256 pin only"
    fi
done
echo "✅ Sources verified in $DEST"
