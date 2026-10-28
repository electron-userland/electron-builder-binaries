#!/usr/bin/env bash
# =============================================================================
# NSIS plugin license helpers
# =============================================================================
# Sourced by nsis-windows.sh to ship the license terms of every third-party plugin it
# bundles, and runnable on its own to check a built bundle:
#
#   nsis-plugin-licenses.sh verify <nsis-bundle-dir>
#
# Layout inside the bundle (next to LICENSE, NSIS's own COPYING):
#   LICENSES/<plugin>/<path in the archive>  license / readme files from the plugin's own download
#   LICENSES/<plugin>/<file>                 license files pinned from the plugin's source repository
#   LICENSES/plugin-dlls.tsv                 "<arch>/<dll><TAB><plugin>" for every DLL in windows/Plugins
#                                            ("NSIS" for the plugins built from NSIS, covered by windows/COPYING)
#   LICENSES/README.md                       where each plugin came from and which license files it ships
#
# Bash 3.2 compatible (nsis-combine.sh and the test suite run on macOS).
# =============================================================================

# A readme whose content matches this states license terms
LICENSE_TEXT_RE='licen[cs]e|permission is (hereby )?granted|public domain'

# Is this archive member a license / readme document? (by base name, case-insensitive)
_is_license_doc() {
    local name
    name=$(basename "$1" | tr '[:upper:]' '[:lower:]')
    case "$name" in
        *.nsh|*.nsi|*.dll|*.exe|*.lib|*.c|*.cpp|*.h|*.rc|*.ico|*.bmp|*.png) return 1 ;;
    esac
    case "$name" in
        *licen[cs]e*|*copying*|*copyright*|notice*|*lgpl*|*gpl*.txt|*clarification*|readme*|authors*|credits*) ;;
        *) return 1 ;;
    esac
    case "$name" in
        *.txt|*.md|*.htm|*.html|*.rtf|*.markdown) return 0 ;;
        *.*) return 1 ;;
        *) return 0 ;;
    esac
}

_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

# collect_plugin_licenses <plugin> <extracted-archive-dir> <licenses-dir>
# Copies the license / readme documents the plugin's archive ships, keeping their paths.
collect_plugin_licenses() {
    local plugin="$1" src="$2" dest="$3/$1" count=0 file rel
    mkdir -p "$dest"
    while IFS= read -r file; do
        _is_license_doc "$file" || continue
        rel="${file#"$src"/}"
        mkdir -p "$dest/$(dirname "$rel")"
        cp "$file" "$dest/$rel"
        count=$((count + 1))
    done < <(find "$src" -type f ! -path '*/.git/*' | sort)
    echo "    📄 $plugin: $count license/readme file(s) from the plugin archive"
}

# _has_license_terms <dir>: a license file by name, or a document that states license terms
_has_license_terms() {
    local file name
    [ -d "$1" ] || return 1
    while IFS= read -r file; do
        name=$(basename "$file" | tr '[:upper:]' '[:lower:]')
        case "$name" in
            *licen[cs]e*|*copying*|*lgpl*|*gpl*|*clarification*|notice*) return 0 ;;
        esac
        grep -qiE "$LICENSE_TEXT_RE" "$file" && return 0
    done < <(find "$1" -type f)
    return 1
}

# fetch_plugin_license <plugin> <url> <sha256> <path> <licenses-dir>
# Downloads a license file pinned (by SHA256) from the plugin's source repository at the bundled version
# to LICENSES/<plugin>/<path>.
fetch_plugin_license() {
    local plugin="$1" url="$2" expected="$3" out="$5/$1/$4" actual
    mkdir -p "$(dirname "$out")"
    if ! curl -fsSL --retry 3 --retry-delay 2 --max-time 60 "$url" -o "$out"; then
        echo "❌ Failed to download the $plugin license from $url"
        return 1
    fi
    actual=$(_sha256 "$out")
    if [ "$actual" != "$expected" ]; then
        echo "❌ Checksum mismatch for the $plugin license $url"
        echo "   Expected: $expected"
        echo "   Got:      $actual"
        rm -f "$out"
        return 1
    fi
    echo "    📄 $plugin: $4 from its source repository"
}

# plugin_dll_snapshot <plugins-dir>  ->  "<arch>/<dll> <crc>" lines, sorted
plugin_dll_snapshot() {
    (cd "$1" && find . -type f -iname '*.dll' -exec cksum {} + | awk '{sub(/^\.\//, "", $3); print $3 " " $1}' | LC_ALL=C sort)
}

# record_plugin_dlls <owner> <snapshot-before> <plugins-dir> <licenses-dir>
# Attributes every DLL added or replaced since <snapshot-before> to <owner>. The last owner of a path wins.
record_plugin_dlls() {
    local owner="$1" before="$2" plugins_dir="$3" tsv="$4/plugin-dlls.tsv" after
    after="$before.after"
    plugin_dll_snapshot "$plugins_dir" > "$after"
    LC_ALL=C comm -13 "$before" "$after" | awk -v owner="$owner" '{print $1 "\t" owner}' >> "$tsv"
    rm -f "$after"
}

# verify_plugin_licenses <nsis-bundle-dir>
# Fails when a DLL in windows/Plugins has no owner, or its owner ships no license terms.
verify_plugin_licenses() {
    local bundle="$1" licenses="$1/LICENSES" tsv="$1/LICENSES/plugin-dlls.tsv" missing=() rel owner
    if [ ! -f "$tsv" ]; then
        echo "❌ $tsv not found: the bundle does not record which plugin each DLL came from"
        return 1
    fi
    while IFS= read -r rel; do
        owner=$(awk -F'\t' -v rel="$rel" '$1 == rel {o = $2} END {print o}' "$tsv")
        if [ -z "$owner" ]; then
            missing+=("windows/Plugins/$rel (not attributed to any plugin)")
        elif [ "$owner" = "NSIS" ]; then
            grep -qi 'zlib' "$bundle/windows/COPYING" 2>/dev/null \
                || missing+=("windows/Plugins/$rel (NSIS plugin, but windows/COPYING is missing)")
        elif ! _has_license_terms "$licenses/$owner"; then
            missing+=("windows/Plugins/$rel ($owner: no license file in LICENSES/$owner)")
        fi
    done < <(cd "$bundle/windows/Plugins" && find . -type f -iname '*.dll' | sed 's|^\./||' | sort)
    if [ ${#missing[@]} -gt 0 ]; then
        echo "❌ Plugin DLLs without license terms:"
        printf '     - %s\n' "${missing[@]}"
        return 1
    fi
    echo "  ✓ Every plugin DLL has license terms ($(grep -c . "$tsv" | xargs) DLL records)"
}

# ci_notice <title> <text>: print <text>, and on GitHub Actions also raise it as a notice annotation, which can
# be read through the checks API (no job log download needed)
ci_notice() {
    local title="$1" text="$2" msg
    printf '%s\n%s\n' "--- $title" "$text"
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
        msg=$(printf '%s' "$text" | head -c 30000 | awk '{gsub(/%/, "%25"); gsub(/\r/, "%0D"); printf "%s%%0A", $0}')
        echo "::notice title=$title::$msg"
    fi
}

# report_archive_terms <plugin> <extracted-archive-dir>
# Shows what a plugin's download carries when no license terms were found in it: the file list and every line of
# its text files that mentions a license or copyright, so the terms can be located and pinned.
report_archive_terms() {
    local plugin="$1" src="$2" files lines
    files=$(cd "$src" 2>/dev/null && find . -type f | sed 's|^\./||' | LC_ALL=C sort)
    lines=$(cd "$src" 2>/dev/null && find . -type f ! -iname '*.dll' ! -iname '*.exe' ! -iname '*.lib' ! -iname '*.obj' \
        ! -iname '*.ico' ! -iname '*.bmp' ! -iname '*.png' ! -iname '*.zip' -print0 \
        | xargs -0 grep -niE -I 'licen[cs]e|copyright|\(c\) ?[0-9]|public domain|permission|zlib|gpl|freeware|free software' 2>/dev/null \
        | cut -c1-240 | head -n 80)
    ci_notice "$plugin archive: files" "${files:-(no files)}"
    ci_notice "$plugin archive: license/copyright mentions" "${lines:-(none)}"
}

# plugins_without_terms <licenses-dir>: the owners in plugin-dlls.tsv (other than NSIS) without license terms
plugins_without_terms() {
    local licenses="$1" owner
    awk -F'\t' '{o[$1] = $2} END {for (d in o) if (o[d] != "NSIS") print o[d]}' "$licenses/plugin-dlls.tsv" | LC_ALL=C sort -u \
        | while IFS= read -r owner; do
            _has_license_terms "$licenses/$owner" || echo "$owner"
        done
}

# write_plugin_license_index <licenses-dir> <sources-tsv>
# <sources-tsv> lines: "<plugin><TAB><download url><TAB><sha256>"
write_plugin_license_index() {
    local licenses="$1" sources="$2" plugin url sha files dlls
    {
        echo "# Third-party NSIS plugins"
        echo ""
        echo "NSIS itself, including the plugins built from its source, is covered by \`LICENSE\` (NSIS's \`COPYING\`)."
        echo "Each third-party plugin below keeps its own license; its license files are in \`LICENSES/<plugin>/\`."
        echo "\`plugin-dlls.tsv\` maps every DLL in \`windows/Plugins\` to the plugin it came from."
        while IFS="$(printf '\t')" read -r plugin url sha; do
            [ -n "$plugin" ] || continue
            files=$(cd "$licenses/$plugin" 2>/dev/null && find . -type f | sed 's|^\./||' | sort | sed 's|^|  - |')
            dlls=$(awk -F'\t' -v p="$plugin" '{o[$1] = $2} END {for (d in o) if (o[d] == p) print "  - " d}' "$licenses/plugin-dlls.tsv" | sort)
            echo ""
            echo "## $plugin"
            echo ""
            echo "- Source: $url"
            echo "- SHA256: $sha"
            echo "- License files:"
            echo "${files:-  - (none)}"
            echo "- DLLs:"
            echo "${dlls:-  - (none)}"
        done < "$sources"
    } > "$licenses/README.md"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    set -euo pipefail
    case "${1:-}" in
        verify)
            [ -n "${2:-}" ] || { echo "Usage: $0 verify <nsis-bundle-dir>"; exit 1; }
            verify_plugin_licenses "$2"
            ;;
        *)
            echo "Usage: $0 verify <nsis-bundle-dir>"
            exit 1
            ;;
    esac
fi
