#!/usr/bin/env bash
# =============================================================================
# collect-licenses.sh: lay out LICENSES/ for the portable Ruby + fpm bundle
# =============================================================================
#
#   collect-licenses.sh <install-dir> <ruby-dir-name>
#
# Writes, inside <install-dir>, the layout checked by scripts/verify-licenses.sh:
#   LICENSES/MANIFEST.tsv     "<relative path><TAB><component>" for every binary in the bundle
#   LICENSES/<component>/     that component's license files, copied from where the build got the component:
#     ruby      COPYING, BSDL, LEGAL (+ COPYING.ja, GPL) from the Ruby source tarball; compile-portable-ruby.sh
#               copies them to LICENSES/ruby/ before it deletes the source tree. This script only checks them.
#     fpm       LICENSE of the installed fpm gem (not a binary, but it is the bundle's entry point)
#     openssl   Linux: LICENSE.txt of the static OpenSSL built by compile-openssl.sh ($OPENSSL_PREFIX/LICENSE.txt)
#               macOS: the openssl@3 Homebrew keg's license files
#     zlib, libyaml, libffi, gmp, xz
#               Linux: /usr/share/doc/<debian package>/copyright of the package that provides the library in the
#               build image, plus the /usr/share/common-licenses/* files it refers to
#               macOS: the license files of the Homebrew formula the library was copied from
#     <gem>     a native extension of a gem (e.g. racc's cparse.so): the gem's own COPYING/LICENSE/BSDL files
#   Each third-party library component also gets SOURCE.txt: the package and version it came from and where its
#   source is.
#
# A binary this script does not know is left out of MANIFEST.tsv, so verify-licenses.sh fails and names it.
#
# Environment:
#   VERIFY_LICENSES   path to scripts/verify-licenses.sh (its --list mode is the single binary detector)
#   OPENSSL_PREFIX    Linux: the static OpenSSL install (default /opt/openssl)
#   LICENSE_OS        Linux or Darwin (default: uname); only for tests
#   DEBIAN_DOC_DIR, COMMON_LICENSES_DIR
#                     default /usr/share/doc and /usr/share/common-licenses; only for tests
# =============================================================================
set -euo pipefail

if [ $# -ne 2 ]; then
    echo "Usage: $0 <install-dir> <ruby-dir-name>" >&2
    exit 2
fi
INSTALL_DIR=$1
RUBY_DIR_NAME=$2
RUBY_PREFIX="$INSTALL_DIR/$RUBY_DIR_NAME"
LICENSES="$INSTALL_DIR/LICENSES"
MANIFEST="$LICENSES/MANIFEST.tsv"
OS="${LICENSE_OS:-$(uname)}"
VERIFY_LICENSES="${VERIFY_LICENSES:?VERIFY_LICENSES must point to scripts/verify-licenses.sh}"
DEBIAN_DOC_DIR="${DEBIAN_DOC_DIR:-/usr/share/doc}"
COMMON_LICENSES_DIR="${COMMON_LICENSES_DIR:-/usr/share/common-licenses}"

TAB=$(printf '\t')

die() {
    echo "❌ $*" >&2
    exit 1
}

[ -d "$RUBY_PREFIX" ] || die "Ruby install not found: $RUBY_PREFIX"
[ -f "$VERIFY_LICENSES" ] || die "License guard not found: $VERIFY_LICENSES"
mkdir -p "$LICENSES"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/collect-licenses.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
: > "$WORK/manifest"
: > "$WORK/collected"

# copy_license_files <src-dir> <dest-dir> <glob>...: copies the regular, non-empty top-level files of <src-dir> that
# match a glob (case-insensitive) and prints how many it copied
copy_license_files() {
    local src="$1" dest="$2" count=0 f
    shift 2
    mkdir -p "$dest"
    shopt -s nullglob nocaseglob
    for pattern in "$@"; do
        for f in "$src"/$pattern; do
            [ -f "$f" ] && [ -s "$f" ] || continue
            [ -e "$dest/$(basename "$f")" ] && continue
            cp -L "$f" "$dest/"
            count=$((count + 1))
        done
    done
    shopt -u nullglob nocaseglob
    echo "$count"
}

# ---------------------------------------------------------------------------
# Debian (Linux build image)
# ---------------------------------------------------------------------------

# debian_package_of <library file name>: the one installed package (native arch) that ships */<name>
debian_package_of() {
    local name="$1" native
    native=$(dpkg --print-architecture)
    { dpkg -S "*/$name" 2>/dev/null || true; } |
        sed -n 's/^\([^ :,]*\)\(:[^ :,]*\)\{0,1\}: \/.*/\1\2/p' |
        awk -F: -v native="$native" '$2 == "" || $2 == native || $2 == "all" {print $1}' |
        sort -u
}

# common_license_refs <copyright file>: the names of the /usr/share/common-licenses/<name> files it refers to
# ("/usr/share/common-licenses/GPL-2." and "/usr/share/common-licenses/{MPL-1.1,GPL-2,LGPL-2.1}" forms)
common_license_refs() {
    { grep -oE '/usr/share/common-licenses/(\{[A-Za-z0-9.,_+-]+\}|[A-Za-z0-9._+-]+)' "$1" || true; } |
        awk '{
            name = substr($0, length("/usr/share/common-licenses/") + 1)
            gsub(/[{}]/, "", name)
            n = split(name, parts, ",")
            for (i = 1; i <= n; i++) {
                sub(/\.+$/, "", parts[i])
                if (parts[i] != "") print parts[i]
            }
        }' | sort -u
}

# debian_license <component> <library file name>
debian_license() {
    local component="$1" name="$2" pkgs pkg dest copyright dest_name ref src_pkg
    pkgs=$(debian_package_of "$name")
    [ -n "$pkgs" ] || die "$name: no installed Debian package ships it (dpkg -S '*/$name'); cannot find its license"
    [ "$(printf '%s\n' "$pkgs" | awk 'END {print NR}')" -eq 1 ] ||
        die "$name: several Debian packages ship it ($(echo "$pkgs" | tr '\n' ' ')); cannot tell which was bundled"
    pkg=$pkgs
    grep -qxF "$component$TAB$pkg" "$WORK/collected" && return 0

    copyright="$DEBIAN_DOC_DIR/$pkg/copyright"
    [ -s "$copyright" ] || die "$name: $copyright is missing or empty (package $pkg)"
    dest="$LICENSES/$component"
    mkdir -p "$dest"
    dest_name=copyright
    [ -e "$dest/$dest_name" ] && dest_name="copyright.$pkg"
    cp -L "$copyright" "$dest/$dest_name"

    # The copyright file names license texts in /usr/share/common-licenses instead of including them
    while IFS= read -r ref; do
        ref="$COMMON_LICENSES_DIR/$ref"
        if [ -f "$ref" ]; then
            mkdir -p "$dest/common-licenses"
            cp -L "$ref" "$dest/common-licenses/"
        else
            echo "  ⚠️ $copyright refers to $ref, which is not in the image" >&2
        fi
    done < <(common_license_refs "$copyright")

    src_pkg=$(dpkg-query -W -f='${source:Package} ${source:Version}' "$pkg")
    {
        echo "$name: Debian package $pkg $(dpkg-query -W -f='${Version}' "$pkg") ($(dpkg --print-architecture)), in the build image (Debian $(cat /etc/debian_version 2>/dev/null || echo unknown))."
        echo "  License: $dest_name (= $copyright)"
        echo "  Source package: $src_pkg"
        echo "  Source: https://snapshot.debian.org/package/${src_pkg%% *}/ (or: apt-get source ${src_pkg%% *}=${src_pkg#* })"
    } >> "$dest/SOURCE.txt"
    printf '%s\t%s\n' "$component" "$pkg" >> "$WORK/collected"
    echo "  📄 $component: $copyright ($pkg)"
}

# ---------------------------------------------------------------------------
# Homebrew (macOS)
# ---------------------------------------------------------------------------

# brew_formula_of <component>
brew_formula_of() {
    case "$1" in
        openssl) echo "openssl@3" ;;
        zlib | libyaml | gmp | xz) echo "$1" ;;
        *) return 1 ;;
    esac
}

# brew_license <component> <library file name>
brew_license() {
    local component="$1" name="$2" formula prefix dest count version url=""
    formula=$(brew_formula_of "$component") || die "$name: no Homebrew formula known for component $component"
    grep -qxF "$component$TAB$formula" "$WORK/collected" && return 0

    prefix=$(brew --prefix "$formula")
    [ -d "$prefix" ] || die "$name: Homebrew formula $formula is not installed ($prefix)"
    dest="$LICENSES/$component"
    # Homebrew installs a formula's top-level license (copying*, copyright*, license*, licence*) and README files into
    # the keg root (Library/Homebrew/metafiles.rb)
    count=$(copy_license_files "$prefix" "$dest" 'LICENSE*' 'LICENCE*' 'COPYING*' 'COPYRIGHT*' 'NOTICE*')
    if [ "$count" -eq 0 ]; then
        # zlib states its license in README
        count=$(copy_license_files "$prefix" "$dest" 'README*')
        [ "$count" -eq 0 ] || echo "  ⚠️ $formula: no LICENSE/COPYING file in $prefix, shipping its README (which states the license)" >&2
    fi
    [ "$count" -gt 0 ] || die "$name: no license file found in the Homebrew keg $prefix ($formula)"

    version=$(brew list --versions "$formula" | head -n 1)
    if command -v jq >/dev/null 2>&1; then
        url=$(brew info --json=v2 "$formula" | jq -r '.formulae[0].urls.stable.url // empty' || true)
    fi
    {
        echo "$name: Homebrew formula ${version:-$formula}."
        echo "  Source: ${url:-run \`brew info $formula\` for the source URL}"
    } >> "$dest/SOURCE.txt"
    printf '%s\t%s\n' "$component" "$formula" >> "$WORK/collected"
    echo "  📄 $component: $prefix ($formula)"
}

# ---------------------------------------------------------------------------
# Components
# ---------------------------------------------------------------------------

# library_component <file name>: the component a bundled shared library belongs to
library_component() {
    case "$1" in
        libz.*) echo zlib ;;
        libyaml-*) echo libyaml ;;
        libffi.*) echo libffi ;;
        libgmp.* | libgmpxx.*) echo gmp ;;
        liblzma.*) echo xz ;;
        libssl.* | libcrypto.*) echo openssl ;;
        *) return 1 ;;
    esac
}

# library_license <component> <library file name>
library_license() {
    if [ "$OS" = Darwin ]; then
        brew_license "$1" "$2"
    else
        debian_license "$1" "$2"
    fi
}

# gem_license <path of a native extension>: prints the gem's component name after copying its license files
gem_license() {
    local path="$1" base rest gem_dir_name gem_dir component count
    base="${path%%/extensions/*}"
    rest="${path#"$base"/extensions/}"
    # rest = <platform>/<ruby abi>/<gem>-<version>/...
    gem_dir_name=$(printf '%s\n' "$rest" | cut -d/ -f3)
    gem_dir="$INSTALL_DIR/$base/gems/$gem_dir_name"
    component="${gem_dir_name%-*}"
    [ -d "$gem_dir" ] || die "$path: gem directory $gem_dir not found"
    if ! grep -qxF "$component${TAB}gem" "$WORK/collected"; then
        count=$(copy_license_files "$gem_dir" "$LICENSES/$component" 'LICENSE*' 'LICENCE*' 'COPYING*' 'BSDL' 'MIT-LICENSE*' 'LEGAL*')
        [ "$count" -gt 0 ] || die "$path: no license file in gem directory $gem_dir"
        printf '%s\tgem\n' "$component" >> "$WORK/collected"
        echo "  📄 $component: $gem_dir" >&2
    fi
    echo "$component"
}

add() {
    printf '%s\t%s\n' "$1" "$2" >> "$WORK/manifest"
}

echo "📄 Collecting component licenses into $LICENSES"

# Ruby: copied from the source tree by compile-portable-ruby.sh
for f in COPYING BSDL LEGAL; do
    [ -s "$LICENSES/ruby/$f" ] || die "LICENSES/ruby/$f is missing: compile-portable-ruby.sh copies it from the Ruby source tree"
done
echo "  📄 ruby: $(cd "$LICENSES/ruby" && echo *)"

# fpm: from the installed gem
shopt -s nullglob
fpm_licenses=("$RUBY_PREFIX"/gems/gems/fpm-*/LICENSE)
shopt -u nullglob
[ "${#fpm_licenses[@]}" -eq 1 ] || die "expected one installed fpm gem LICENSE, found ${#fpm_licenses[@]}"
mkdir -p "$LICENSES/fpm"
cp "${fpm_licenses[0]}" "$LICENSES/fpm/LICENSE"
echo "  📄 fpm: ${fpm_licenses[0]}"

# OpenSSL on Linux: static, inside bin/ruby
if [ "$OS" != Darwin ]; then
    openssl_license="${OPENSSL_PREFIX:-/opt/openssl}/LICENSE.txt"
    [ -s "$openssl_license" ] || die "OpenSSL license not found at $openssl_license"
    mkdir -p "$LICENSES/openssl"
    cp "$openssl_license" "$LICENSES/openssl/LICENSE.txt"
    echo "  📄 openssl: $openssl_license"
fi

# Map every binary in the bundle to its components (read on fd 3: dpkg/brew must not consume the list)
while IFS= read -r bin <&3; do
    case "$bin" in
        "$RUBY_DIR_NAME/bin/ruby")
            add "$bin" ruby
            # Linux links OpenSSL statically (compile-openssl.sh); patch-portable-ruby.sh fails if it is not
            [ "$OS" = Darwin ] || add "$bin" openssl
            ;;
        */extensions/*/*/*/*)
            component=$(gem_license "$bin")
            add "$bin" "$component"
            ;;
        "$RUBY_DIR_NAME/lib/"*)
            name="${bin#"$RUBY_DIR_NAME/lib/"}"
            case "$name" in
                */*) echo "  ⚠️ $bin: no license mapping for this binary" >&2; continue ;;
            esac
            if ! component=$(library_component "$name"); then
                echo "  ⚠️ $bin: no license mapping for this library" >&2
                continue
            fi
            library_license "$component" "$name"
            add "$bin" "$component"
            ;;
        *)
            echo "  ⚠️ $bin: no license mapping for this binary" >&2
            ;;
    esac
done 3< <(bash "$VERIFY_LICENSES" --list "$INSTALL_DIR")

{
    echo "# <path relative to the bundle root><TAB><component>; license files are in LICENSES/<component>/"
    echo "# Generated by packages/fpm/assets/collect-licenses.sh and checked by scripts/verify-licenses.sh"
    sort -u "$WORK/manifest"
} > "$MANIFEST"
echo "  ✓ $(sort -u "$WORK/manifest" | awk 'END {print NR}') entries in LICENSES/MANIFEST.tsv"
