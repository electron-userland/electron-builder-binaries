#!/usr/bin/env bash
#
# Derive the set of Wine system DLLs that electron-builder's bundled Windows tools actually
# load, by running each tool under a given Wine with WINEDEBUG=+loaddll and collecting every
# DLL resolved out of windows\system32 / windows\syswow64.
#
# Used to (re)generate the static whitelist build-wine.sh prunes the Wine bundle to: the keep-list is
# a committed artifact (wine-keep-dlls.txt, next to this script). build-wine.sh only READS that file —
# it never runs this trace. Run this by hand to refresh the list on a Wine/tool bump. Because the trace
# downloads + executes AV-flagged Windows tooling, run it on CI/a throwaway box only, never on a dev machine.
#
# Usage:
#   generate-trace-exes.sh <work_dir>      # overwrites ./wine-keep-dlls.txt with the freshly traced list
# Env:
#   WINE_BIN     path to the wine binary to trace under (default: `wine` on PATH)
#   WINEPREFIX   wine prefix to use (default: the wine's default prefix)
#
# Output: writes wine-keep-dlls.txt (sorted-unique lowercase DLL names, with a header) next to this
#         script. All human-readable progress goes to stderr.
set -uo pipefail

WORK_DIR="${1:?usage: generate-trace-exes.sh <work_dir>}"
WINE_BIN="${WINE_BIN:-wine}"

log() { echo "$@" >&2; }

# Run a command with a hard time cap (portable — macOS ships no GNU `timeout`); kills it after
# $1 seconds so a Wine hang fails fast instead of stalling the build. Mirrors test.sh's bound().
bound() {
    local secs="$1"; shift
    "$@" &
    local pid=$!
    ( sleep "$secs"; kill -9 "$pid" 2>/dev/null ) >/dev/null 2>&1 &
    local guard=$! rc=0
    wait "$pid" 2>/dev/null || rc=$?
    kill "$guard" 2>/dev/null || true
    return "$rc"
}

DOWNLOAD_DIR="$WORK_DIR/downloads"
UNPACK_DIR="$WORK_DIR/unpacked"
mkdir -p "$DOWNLOAD_DIR" "$UNPACK_DIR"

CODESIGN="https://github.com/electron-userland/electron-builder-binaries/releases/download/win-codesign@1.3.0"
WIX="https://github.com/electron-userland/electron-builder-binaries/releases/download/wix-4.0.0.5512.2"
NSIS="https://github.com/electron-userland/electron-builder-binaries/releases/download/nsis@2.0.0"

# url|sha256 — the toolchains electron-builder runs under this Wine bundle:
#   win-codesign@1.3.0 → rcedit, signtool/osslsigncode, Windows Kits (makeappx), Azure Trusted Signing
#   wix-4.0.0.5512.2   → candle.exe / light.exe (MSI; 32-bit .NET, run under Wine Mono)
#   nsis@2.0.0         → makensis
ARCHIVES="
$CODESIGN/rcedit-windows-2_0_0.zip|84ea279c5d94977fecffbe0f21b073318575dc631a3dae46fadb14309f2eef11
$CODESIGN/win-codesign-windows-x64.zip|40d621aad7593e6298ce1d24798760dcefb053f358be891d74c95386ac2ac50b
$CODESIGN/windows-kits-bundle-10_0_26100_0.zip|2eeb955e580103e1bbecf9666dca87b141c3bb73ad99ead64bb8821755694ecd
$CODESIGN/ats-bundle-1_0_95.zip|93e1441cd8c60f7b7a57a3e0e20a2109994e33a7f42bd04c998204a1928f9f2f
$WIX/wix-4.0.0.5512.2.7z|fe677fcd837b18c9b912985d91636bbd8a1e800c3b3a6a841b6f96e89624e839
$NSIS/nsis-bundle-3.12.tar.gz|e2c84b314160604d5132cb15b65fee92981320572902b3a1aa17a9a0d632cd58
"

# Resolve a 7-Zip binary for the WiX .7z (macOS runners ship 7-Zip; Linux uses p7zip).
SEVENZ=""
for _cmd in 7z 7za 7zz; do
    command -v "$_cmd" >/dev/null 2>&1 && { SEVENZ="$_cmd"; break; }
done

extract() {
    local file="$1" dest="$2"
    mkdir -p "$dest"
    case "$file" in
        *.zip)    unzip -q -o "$file" -d "$dest" ;;
        *.7z)
            if [ -z "$SEVENZ" ]; then
                log "❌ no 7-Zip binary (7z/7za/7zz) found for $file — install p7zip/7-Zip;"
                log "   WiX candle/light DLLs cannot be traced without it, so the bundle would drop them."
                return 1
            fi
            "$SEVENZ" x -y -o"$dest" "$file" >/dev/null ;;
        *.tar.gz) tar -xzf "$file" -C "$dest" ;;
        *.tar.xz) tar -xJf "$file" -C "$dest" ;;
        *) log "❌ unknown archive format: $file"; return 1 ;;
    esac
}

log "📥 Downloading + extracting trace toolchains"
while IFS='|' read -r URL SHA; do
    [ -z "$URL" ] && continue
    NAME="$(basename "$URL")"
    DEST="$DOWNLOAD_DIR/$NAME"
    log "  ⬇️  $NAME"
    curl -fsSL --retry 3 --retry-delay 2 --max-time 600 -o "$DEST" "$URL"
    ACTUAL="$(shasum -a 256 "$DEST" | awk '{print $1}')"
    if [ "$ACTUAL" != "$SHA" ]; then
        log "❌ checksum mismatch for $NAME: expected $SHA got $ACTUAL"
        exit 1
    fi
    extract "$DEST" "$UNPACK_DIR/${NAME%.*}" || exit 1
done <<< "$ARCHIVES"

# Run every discovered .exe under Wine with +loaddll, harmlessly (no args), and capture the
# system DLLs it resolves. A no-arg invocation still forces the loader to map the import chain
# (for .NET tools like candle/light it also spins up the runtime), which is what we need.
log "🧪 Tracing tool DLL loads under $WINE_BIN"
TRACE_LOG="$WORK_DIR/loaddll.log"
: > "$TRACE_LOG"
while IFS= read -r exe; do
    log "  🔎 $(basename "$exe")"
    bound 90 env WINEDEBUG=+loaddll MONO_LOG_LEVEL=debug MONO_LOG_MASK=asm "$WINE_BIN" "$exe" \
        >/dev/null 2>>"$TRACE_LOG" || true
done < <(find "$UNPACK_DIR" -type f -iname '*.exe' | sort -u)

# Keep only DLLs resolved out of the Wine windows dirs (system32 / syswow64); the tools' own
# bundled DLLs (e.g. wix.dll next to candle.exe) and Wine Mono assemblies live elsewhere and are
# ignored. Wine prints the wide path with escaped separators (...\\system32\\foo.dll), so match
# one-or-more backslashes around the dir name rather than a single one.
# Build the new list in a temp file first, then move it into place only if the trace actually
# discovered DLLs — a failed/empty trace must never clobber the committed whitelist.
KEEP_FILE="$(cd "$(dirname "$0")" && pwd)/wine-keep-dlls.txt"
TMP_KEEP="$WORK_DIR/wine-keep-dlls.txt"
{
    echo "# AUTO-GENERATED by generate-trace-exes.sh — do not edit by hand."
    echo "# Wine system DLLs (system32 / syswow64) that electron-builder's bundled Windows tools load."
    echo "# build-wine.sh prunes the Wine bundle to these (plus a small bootstrap floor in build-wine.sh)."
    echo "#"
    echo "# Regenerate after a Wine or tool version bump:   bash assets/generate-trace-exes.sh <work_dir>"
    echo "# CI ONLY — the trace downloads + executes AV-flagged Windows tooling (rcedit, NSIS,"
    echo "# WriteZipToSetup, signtool); never run it on a developer machine."
    grep -aoiE '\\+(system32|syswow64)\\+[a-z0-9_.+-]+\.dll' "$TRACE_LOG" \
        | grep -aoiE '[a-z0-9_.+-]+\.dll$' \
        | tr '[:upper:]' '[:lower:]' \
        | sort -u
} > "$TMP_KEEP"

COUNT="$(grep -cvE '^[[:space:]]*#' "$TMP_KEEP")"
if [ "$COUNT" -eq 0 ]; then
    log "❌ trace discovered no system DLLs — keeping the existing $(basename "$KEEP_FILE"); aborting"
    exit 1
fi
mv "$TMP_KEEP" "$KEEP_FILE"
log "✅ Wrote $COUNT DLLs to $(basename "$KEEP_FILE")"

# Wine Mono assembly-load evidence. Managed assemblies are invisible to +loaddll (Mono mmaps them
# via mono_image_open, not LoadLibraryW), so MONO_LOG_MASK=asm is what reveals what candle/light
# actually load. This file is committed as EVIDENCE — it does not drive the prune (wine-mono-prune.txt
# does). It exists so a denylist edit can be checked: nothing candle/light load should match a glob.
ASSETS_DIR="$(cd "$(dirname "$0")" && pwd)"
MONO_LOADED_FILE="$ASSETS_DIR/wine-mono-loaded.txt"
MONO_TMP="$WORK_DIR/wine-mono-loaded.txt"
{
    echo "# AUTO-GENERATED by generate-trace-exes.sh — evidence, NOT a prune driver."
    echo "# .NET assemblies WiX candle/light actually loaded under Wine Mono (MONO_LOG_MASK=asm)."
    echo "# wine-mono-prune.txt (the denylist) must never list anything that appears here."
    grep -aoE "loaded assembly from location: '[^']+'" "$TRACE_LOG" \
        | sed -E "s/.*location: '([^']+)'/\1/" \
        | sed -E 's#.*[\\/]##' \
        | sort -u
} > "$MONO_TMP"

if [ "$(grep -cvE '^[[:space:]]*#' "$MONO_TMP")" -gt 0 ]; then
    mv "$MONO_TMP" "$MONO_LOADED_FILE"
    log "✅ Wrote $(grep -cvE '^[[:space:]]*#' "$MONO_LOADED_FILE") loaded Mono assemblies to $(basename "$MONO_LOADED_FILE")"
    # Safety cross-check: warn if the denylist would delete anything candle/light actually loaded.
    DENY_FILE="$ASSETS_DIR/wine-mono-prune.txt"
    if [ -f "$DENY_FILE" ]; then
        while IFS= read -r _glob; do
            case "$_glob" in ''|\#*) continue ;; esac
            while IFS= read -r _asm; do
                case "$_asm" in ''|\#*) continue ;; esac
                case "${_asm%.dll}" in $_glob) log "⚠️  DENYLIST CONFLICT: glob '$_glob' matches loaded assembly '$_asm' — remove it from wine-mono-prune.txt" ;; esac
            done < "$MONO_LOADED_FILE"
        done < "$DENY_FILE"
    fi
else
    log "ℹ️  No Mono assembly loads captured (no .NET tool traced, or MONO_LOG unsupported by this Wine Mono)"
fi
