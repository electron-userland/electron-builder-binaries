---
"icons": minor
---

feat(icons): icon-tool CLI accepts space-delimited arguments

The CLI now parses both the space-delimited `--key value` form and the original
concatenated `--key=value` form, so callers no longer have to build
`--input=<path>` strings. Parsing is backward compatible — existing `--key=value`
invocations continue to work unchanged. Values may contain spaces or `=`
characters when passed as separate argv tokens.
