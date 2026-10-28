#!/usr/bin/env bash
# =============================================================================
# collect-licenses.sh: lay out LICENSES/ in an AppImage tools bundle for scripts/verify-licenses.sh
# =============================================================================
# Sourced (not run) by build-appimage.sh, appimage-linux.sh and bundle-and-compress.sh.
#
#   LICENSES/MANIFEST.tsv          "<bundle path or glob><TAB><component>" for every shipped binary
#   LICENSES/<component>/          the component's license files, copied from its pinned source tree, the build
#                                  image (/usr/share/doc/<pkg>/copyright) or the Homebrew keg, never written by hand
#   LICENSES/SOURCES.d/<name>.md   per-build list of the exact sources (versions, commits, packages); folded into
#                                  LICENSES/SOURCES.md by lic_finalize_sources once all builds are merged
#
# Component names:
#   squashfs-tools, desktop-file-utils, openjpeg, zstd-<version>, type2-runtime, libfuse, ...   upstream projects
#   debian-<binary package>                     a library copied from the Ubuntu build image (Linux)
#   homebrew-<formula>-<version>                a dylib copied from a Homebrew keg (macOS)
# Every function returns non-zero on failure (they are also called where set -e does not apply).
#
# Portable bash (macOS bash 3.2 included).
# =============================================================================

LIC_DIR=""
LIC_SOURCES=""
# Set by lic_system_lib / lic_debian_lib / lic_homebrew_lib: the component of the last library looked up
LIC_COMPONENT=""
# Roots of .deb packages extracted with dpkg -x (and their control files with dpkg-deb -e into <root>/DEBIAN), e.g.
# the i386 libappindicator packages, which are not installed and so unknown to dpkg -S
LIC_DEB_ROOTS="${LIC_DEB_ROOTS:-}"
# Prefix for /usr/share/doc and /usr/share/common-licenses (tests only)
LIC_SYSROOT="${LIC_SYSROOT:-}"

_lic_err() {
    echo "❌ [licenses] $*" >&2
    return 1
}

# _lic_sha256 <file>
_lic_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        _lic_err "no sha256sum or shasum"
    fi
}

# _lic_valid_component <name>: a single directory name (no /, not . or ..)
_lic_valid_component() {
    case "$1" in
        ''|.|..|*/*|*\\*|*"	"*) _lic_err "invalid component name: '$1'" ;;
    esac
}

# lic_init <bundle dir> <sources fragment name> <fragment heading>
# Starts (or continues) the LICENSES/ layout of a bundle.
lic_init() {
    [ $# -eq 3 ] || { _lic_err "usage: lic_init <bundle dir> <fragment name> <heading>"; return 1; }
    LIC_DIR="$1/LICENSES"
    LIC_SOURCES="$LIC_DIR/SOURCES.d/$2.md"
    mkdir -p "$LIC_DIR/SOURCES.d" || return 1
    [ -f "$LIC_DIR/MANIFEST.tsv" ] || : > "$LIC_DIR/MANIFEST.tsv" || return 1
    if [ ! -f "$LIC_SOURCES" ]; then
        printf '## %s\n\n' "$3" > "$LIC_SOURCES" || return 1
    fi
}

_lic_require_init() {
    [ -n "$LIC_DIR" ] && [ -d "$LIC_DIR" ] || _lic_err "lic_init was not called"
}

# lic_copy <component> <license file> [<name in LICENSES/<component>/>]
# The file must be non-empty. Copying the same name twice is fine only if the contents are identical.
lic_copy() {
    _lic_require_init || return 1
    local component="$1" src="$2" name="${3:-}" dest
    _lic_valid_component "$component" || return 1
    [ -n "$name" ] || name=$(basename "$src")
    if [ ! -f "$src" ] || [ ! -s "$src" ]; then
        _lic_err "$component: license file missing or empty: $src"
        return 1
    fi
    dest="$LIC_DIR/$component/$name"
    mkdir -p "$LIC_DIR/$component" || return 1
    if [ -e "$dest" ]; then
        cmp -s "$src" "$dest" || { _lic_err "$component: $name already exists with different contents (from $src)"; return 1; }
        return 0
    fi
    cp "$src" "$dest" || return 1
    chmod 0644 "$dest" || return 1
}

# lic_write <component> <name> <text>: a notice this build writes itself (e.g. a modification notice), never the
# license text, which always comes from the component's source
lic_write() {
    _lic_require_init || return 1
    local tmp rc=0
    tmp=$(mktemp "${TMPDIR:-/tmp}/lic-write.XXXXXX") || return 1
    printf '%s\n' "$3" > "$tmp" || rc=1
    [ "$rc" -ne 0 ] || lic_copy "$1" "$tmp" "$2" || rc=1
    rm -f "$tmp"
    return "$rc"
}

# lic_record <bundle path or glob> <component>: a MANIFEST.tsv line (once)
lic_record() {
    _lic_require_init || return 1
    local path="$1" component="$2" line
    _lic_valid_component "$component" || return 1
    case "$path" in
        ''|/*|../*|*/../*) _lic_err "manifest path must be relative to the bundle: '$path'"; return 1 ;;
    esac
    line=$(printf '%s\t%s' "$path" "$component")
    grep -qxF "$line" "$LIC_DIR/MANIFEST.tsv" 2>/dev/null || printf '%s\n' "$line" >> "$LIC_DIR/MANIFEST.tsv" || return 1
}

# lic_source <markdown line>: one line of this build's SOURCES fragment (once)
lic_source() {
    _lic_require_init || return 1
    grep -qxF -- "$1" "$LIC_SOURCES" 2>/dev/null || printf '%s\n' "$1" >> "$LIC_SOURCES" || return 1
}

# lic_fetch <component> <name> <sha256> <url> [<fallback url>...]
# Downloads a license file published at a pinned tag/commit; the first URL whose content matches the SHA256 wins.
lic_fetch() {
    _lic_require_init || return 1
    local component="$1" name="$2" sha="$3" tmp url actual rc=1
    shift 3
    [ $# -gt 0 ] || { _lic_err "$component/$name: no URL"; return 1; }
    tmp=$(mktemp "${TMPDIR:-/tmp}/lic-fetch.XXXXXX") || return 1
    for url in "$@"; do
        if ! curl -fsSL --retry 3 --retry-delay 2 --max-time 60 "$url" -o "$tmp"; then
            echo "⚠️  [licenses] $component/$name: download failed: $url" >&2
            continue
        fi
        actual=$(_lic_sha256 "$tmp") || break
        if [ "$actual" != "$sha" ]; then
            echo "⚠️  [licenses] $component/$name: SHA256 mismatch for $url (expected $sha, got $actual)" >&2
            continue
        fi
        lic_copy "$component" "$tmp" "$name" && rc=0
        break
    done
    rm -f "$tmp"
    [ "$rc" -eq 0 ] || _lic_err "$component/$name: no URL served the pinned file (sha256 $sha)"
}

# lic_pins_components <pins tsv>: the components the pins file lists, once each
lic_pins_components() {
    awk -F'\t' '/^[^#]/ && NF >= 4 && !seen[$1]++ { print $1 }' "$1"
}

# lic_fetch_pins <pins tsv> <type2-runtime release>
# Fetches every "<component><TAB><name><TAB><sha256><TAB><url> [<url>...]" line of the pins file, and adds every
# "# source: <markdown>" line to the SOURCES fragment. The file must declare "# type2-runtime-release: <release>"
# equal to <release>: the statically linked components change with the runtime release, so a release bump must
# re-check them. "{APPIMAGE_TYPE2_RELEASE}" in a URL or source line is replaced by the release.
lic_fetch_pins() {
    local pins="$1" release="$2" pinned component name sha urls line n=0
    local -a url_list
    [ -f "$pins" ] || { _lic_err "pins file not found: $pins"; return 1; }
    pinned=$(sed -n 's/^# type2-runtime-release:[[:space:]]*\([^[:space:]]*\).*/\1/p' "$pins" | head -n 1)
    if [ -z "$pinned" ] || [ "$pinned" != "$release" ]; then
        _lic_err "$pins is pinned for type2-runtime '$pinned', building '$release': re-check the components statically linked into the runtime (its scripts/docker/Dockerfile, scripts/common/install-dependencies.sh and the strings in the binaries), then update the pins"
        return 1
    fi
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        case "$line" in
            '# source: '*)
                line="${line//\{APPIMAGE_TYPE2_RELEASE\}/$release}"
                lic_source "${line#\# source: }" || return 1
                continue
                ;;
            ''|'#'*) continue ;;
        esac
        IFS=$'\t' read -r component name sha urls <<< "$line"
        if [ -z "$component" ] || [ -z "$name" ] || [ -z "$sha" ] || [ -z "$urls" ]; then
            _lic_err "$pins: malformed line: $line"
            return 1
        fi
        urls="${urls//\{APPIMAGE_TYPE2_RELEASE\}/$release}"
        # space-separated fallback URLs (read -a: no globbing of the ? in query strings)
        read -r -a url_list <<< "$urls"
        lic_fetch "$component" "$name" "$sha" "${url_list[@]}" || return 1
        n=$((n + 1))
    done < "$pins"
    [ "$n" -gt 0 ] || { _lic_err "$pins: no pins"; return 1; }
}

# lic_debian_pkg <component> <package> <version> <source package> <source version> <doc root>
# Copies <doc root>/usr/share/doc/<package>/copyright and every /usr/share/common-licenses/<name> it refers to.
lic_debian_pkg() {
    local component="$1" pkg="$2" version="$3" src="$4" srcver="$5" root="$6" copyright ref refs
    copyright="$root/usr/share/doc/$pkg/copyright"
    lic_copy "$component" "$copyright" copyright || return 1
    # "... can be found in /usr/share/common-licenses/GPL-2." -> GPL-2
    refs=$(grep -o '/usr/share/common-licenses/[A-Za-z0-9._-]*' "$copyright" | sed 's/\.*$//' | sort -u) || true
    while IFS= read -r ref; do
        [ -n "$ref" ] || continue
        lic_copy "$component" "$LIC_SYSROOT$ref" "$(basename "$ref")" || return 1
    done <<< "$refs"
    lic_source "- \`$pkg\` $version (Ubuntu 18.04 package; source package \`$src\` $srcver: https://launchpad.net/ubuntu/+source/$src/$srcver)" || return 1
}

# _lic_control_field <control file> <field>
_lic_control_field() {
    awk -v f="$2" 'index($0, f ":") == 1 { sub("^" f ":[ \t]*", ""); print; exit }' "$1"
}

# lic_debian_lib <library path>: sets LIC_COMPONENT to debian-<package> after copying the package's copyright
lic_debian_lib() {
    local lib="$1" real root pkg owner version src srcver control info
    LIC_COMPONENT=""
    real=$(readlink -f "$lib") || real="$lib"
    # Extracted (not installed) .deb packages
    for root in $LIC_DEB_ROOTS; do
        case "$real" in
            "$root"/*)
                control="$root/DEBIAN/control"
                [ -f "$control" ] || { _lic_err "$lib: $control missing (extract it with dpkg-deb -e)"; return 1; }
                pkg=$(_lic_control_field "$control" Package)
                version=$(_lic_control_field "$control" Version)
                src=$(_lic_control_field "$control" Source)
                [ -n "$src" ] || src="$pkg"
                # "Source: name (version)" when the source version differs
                srcver="$version"
                case "$src" in *"("*")"*) srcver=${src#*(}; srcver=${srcver%)*}; src=${src%% *} ;; esac
                [ -n "$pkg" ] && [ -n "$version" ] || { _lic_err "$lib: no Package/Version in $control"; return 1; }
                LIC_COMPONENT="debian-$pkg"
                lic_debian_pkg "$LIC_COMPONENT" "$pkg" "$version" "$src" "$srcver" "$root" || return 1
                return 0
                ;;
        esac
    done
    # "zlib1g:amd64: /lib/x86_64-linux-gnu/libz.so.1.2.11" (diversion lines start with "diversion by")
    owner=$({ dpkg -S "$lib" 2>/dev/null || dpkg -S "$real" 2>/dev/null; } | grep -v '^diversion by' | head -n 1) || true
    owner=${owner%%: *}
    owner=${owner%%, *}
    [ -n "$owner" ] || { _lic_err "$lib: not owned by any installed package (dpkg -S)"; return 1; }
    # shellcheck disable=SC2016 # dpkg-query format, not shell expansions
    info=$(dpkg-query -W -f='${Version}\t${source:Package}\t${source:Version}' "$owner") || { _lic_err "$lib: dpkg-query $owner failed"; return 1; }
    IFS=$'\t' read -r version src srcver <<< "$info"
    pkg=${owner%%:*}
    [ -n "$version" ] && [ -n "$src" ] || { _lic_err "$lib: incomplete package data for $owner: $info"; return 1; }
    LIC_COMPONENT="debian-$pkg"
    lic_debian_pkg "$LIC_COMPONENT" "$pkg" "$version" "$src" "$srcver" "$LIC_SYSROOT" || return 1
}

# lic_homebrew_lib <library path>: sets LIC_COMPONENT to homebrew-<formula>-<version> after copying the license
# files Homebrew installed in the keg root (from the formula's source tarball)
lic_homebrew_lib() {
    local lib="$1" real rest formula version keg f base lower n=0 rb url license
    LIC_COMPONENT=""
    real=$(readlink -f "$lib") || real="$lib"
    case "$real" in
        */Cellar/*/*/*) ;;
        *) _lic_err "$lib ($real) is not in a Homebrew keg (<prefix>/Cellar/<formula>/<version>/): cannot tell its license"; return 1 ;;
    esac
    rest=${real#*/Cellar/}
    formula=${rest%%/*}
    rest=${rest#*/}
    version=${rest%%/*}
    keg="${real%%/Cellar/*}/Cellar/$formula/$version"
    LIC_COMPONENT="homebrew-$formula-$version"
    for f in "$keg"/*; do
        [ -f "$f" ] || continue
        base=$(basename "$f")
        lower=$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')
        case "$lower" in
            license*|licence*|copying*|copyright*|notice*|patents*)
                lic_copy "$LIC_COMPONENT" "$f" "$base" || return 1
                n=$((n + 1))
                ;;
        esac
    done
    [ "$n" -gt 0 ] || { _lic_err "$lib: Homebrew keg $keg has no LICENSE/COPYING/NOTICE file"; return 1; }
    rb="$keg/.brew/$formula.rb"
    url=""
    license=""
    if [ -f "$rb" ]; then
        url=$(sed -n 's/^[[:space:]]*url[[:space:]]*"\([^"]*\)".*/\1/p' "$rb" | head -n 1)
        license=$(sed -n 's/^[[:space:]]*license[[:space:]]*\(.*\)$/\1/p' "$rb" | head -n 1)
    fi
    lic_source "- Homebrew \`$formula\` $version${license:+ (formula license: $license)}${url:+: $url}" || return 1
}

# lic_system_lib <library path>: lic_debian_lib on Linux, lic_homebrew_lib on macOS
lic_system_lib() {
    case "${LIC_OS:-$(uname -s)}" in
        Linux*|linux) lic_debian_lib "$1" ;;
        Darwin*|darwin) lic_homebrew_lib "$1" ;;
        *) _lic_err "unsupported OS for $1" ;;
    esac
}

# lic_merge <destination bundle> <source bundle>
# Copies the source bundle into the destination. LICENSES/MANIFEST.tsv files are concatenated (duplicates dropped);
# every other path both bundles have must be identical (same file contents, same symlink target), or it fails.
lic_merge() {
    local dest="$1" src="$2" list rel rc=0 tmp
    [ -d "$src" ] || { _lic_err "lic_merge: not a directory: $src"; return 1; }
    mkdir -p "$dest" || return 1
    list=$(mktemp "${TMPDIR:-/tmp}/lic-merge.XXXXXX") || return 1
    (cd "$src" && find . \( -type f -o -type l \) -print) > "$list" || rc=1
    while [ "$rc" -eq 0 ] && IFS= read -r rel; do
        rel=${rel#./}
        [ "$rel" != "LICENSES/MANIFEST.tsv" ] || continue
        if [ -L "$src/$rel" ]; then
            if [ -L "$dest/$rel" ]; then
                [ "$(readlink "$src/$rel")" = "$(readlink "$dest/$rel")" ] || { _lic_err "merge conflict: $rel links to different targets"; rc=1; }
                continue
            fi
        elif [ -f "$dest/$rel" ] && [ ! -L "$dest/$rel" ]; then
            cmp -s "$src/$rel" "$dest/$rel" || { _lic_err "merge conflict: $rel differs between bundles"; rc=1; }
            continue
        fi
        if [ -e "$dest/$rel" ] || [ -L "$dest/$rel" ]; then
            _lic_err "merge conflict: $rel is a file in one bundle and a link in the other"
            rc=1
            continue
        fi
        mkdir -p "$(dirname "$dest/$rel")" && cp -pR "$src/$rel" "$dest/$rel" || rc=1
    done < "$list"
    rm -f "$list"
    [ "$rc" -eq 0 ] || return 1
    if [ -f "$src/LICENSES/MANIFEST.tsv" ]; then
        mkdir -p "$dest/LICENSES" || return 1
        tmp=$(mktemp "${TMPDIR:-/tmp}/lic-manifest.XXXXXX") || return 1
        [ -f "$dest/LICENSES/MANIFEST.tsv" ] || : > "$dest/LICENSES/MANIFEST.tsv" || return 1
        if ! awk 'NF && !seen[$0]++' "$dest/LICENSES/MANIFEST.tsv" "$src/LICENSES/MANIFEST.tsv" > "$tmp" \
            || ! chmod 0644 "$tmp" || ! mv "$tmp" "$dest/LICENSES/MANIFEST.tsv"; then
            rm -f "$tmp"
            return 1
        fi
    fi
}

# lic_finalize_sources <bundle> <header file>: LICENSES/SOURCES.md = header + every SOURCES.d fragment (sorted)
lic_finalize_sources() {
    local bundle="$1" header="$2" f
    [ -d "$bundle/LICENSES/SOURCES.d" ] || { _lic_err "$bundle/LICENSES/SOURCES.d missing"; return 1; }
    [ -s "$header" ] || { _lic_err "SOURCES header missing: $header"; return 1; }
    {
        cat "$header"
        for f in "$bundle"/LICENSES/SOURCES.d/*.md; do
            [ -f "$f" ] || continue
            echo ""
            cat "$f"
        done
    } > "$bundle/LICENSES/SOURCES.md" || return 1
    rm -rf "$bundle/LICENSES/SOURCES.d"
}
