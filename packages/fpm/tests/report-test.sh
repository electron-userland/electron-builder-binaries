#!/usr/bin/env bash
# CI helper (build-fpm.yaml): reports a smoke test log as one GitHub Actions annotation (notice when every check
# passed, error otherwise). Usage: LABEL=<runner/image> report-test.sh <test.log>
set -uo pipefail

log="${1:?usage: report-test.sh <test.log>}"
[ -f "$log" ] || exit 0
enc() { sed -e 's/%/%25/g' -e 's/\r//g' | awk '{printf "%s%%0A", $0}'; }
if grep -q ' 0 failed' "$log" && ! grep -Eq ' [1-9][0-9]* failed' "$log"; then lvl=notice; else lvl=error; fi
echo "::$lvl title=smoke test (${LABEL:-})::$(grep -v '^     ' "$log" | tail -n 60 | enc)"
