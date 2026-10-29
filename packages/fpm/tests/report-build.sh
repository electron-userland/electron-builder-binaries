#!/usr/bin/env bash
# CI helper (build-fpm.yaml): reports the fpm toolset build as GitHub Actions annotations, since job logs are not always
# retrievable through the API (e.g. by automation) while annotations are. Run from the repository root.
#   - one notice per built archive with its size, and the native tools' VERSION.txt
#   - on failure ($JOB_STATUS != success), the tail of packages/fpm/build/build.log and of the native build logs
set -uo pipefail

enc() { sed -e 's/%/%25/g' -e 's/\r//g' | awk '{printf "%s%%0A", $0}'; }
for a in packages/fpm/out/fpm/*.7z; do
    [ -f "$a" ] && echo "::notice title=$(basename "$a")::$(wc -c <"$a" | tr -d ' ') bytes"
done
for v in packages/fpm/build/native-*/VERSION.txt; do
    [ -f "$v" ] && echo "::notice title=$(basename "$(dirname "$v")")::$(enc <"$v")"
done
if [ "${JOB_STATUS:-}" != "success" ]; then
    if [ -f packages/fpm/build/build.log ]; then
        echo "::error title=build.log (tail)::$(tail -n 60 packages/fpm/build/build.log | enc)"
    fi
    for log in packages/fpm/build/work-native-*/*.log packages/fpm/build/work-native-*/*/*.log; do
        [ -f "$log" ] && echo "::error title=${log#packages/fpm/build/} (tail)::$(tail -n 40 "$log" | enc)"
    done
fi
exit 0
