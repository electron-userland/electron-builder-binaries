#!/usr/bin/env bash
# CI helper (build-archive.yaml): reports the archive toolset build as GitHub Actions annotations, since job logs are
# not always retrievable through the API (e.g. by automation) while annotations are. Run from the repository root.
#   - one notice per built archive with its size, and the bundle's VERSION.txt
#   - on failure ($JOB_STATUS != success), the tail of packages/archive/build/build.log and of the configure/make logs
set -uo pipefail

enc() { sed -e 's/%/%25/g' -e 's/\r//g' | awk '{printf "%s%%0A", $0}'; }
for a in packages/archive/out/archive/*.7z; do
    [ -f "$a" ] && echo "::notice title=$(basename "$a")::$(wc -c <"$a" | tr -d ' ') bytes"
done
for v in packages/archive/build/stage-*/VERSION.txt; do
    [ -f "$v" ] && echo "::notice title=$(basename "$(dirname "$v")")::$(enc <"$v")"
done
if [ "${JOB_STATUS:-}" != "success" ]; then
    if [ -f packages/archive/build/build.log ]; then
        echo "::error title=build.log (tail)::$(tail -n 80 packages/archive/build/build.log | enc)"
    fi
    # the newest configure/make logs are the ones that failed
    for log in $(ls -t packages/archive/build/work-*/*.log packages/archive/build/work-*/*/*.log packages/archive/build/work-*/*/*/*.log 2>/dev/null | head -n 3); do
        echo "::error title=${log#packages/archive/build/} (tail)::$(tail -n 40 "$log" | enc)"
    done
fi
exit 0
