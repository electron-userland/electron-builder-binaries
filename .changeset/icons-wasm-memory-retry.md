---
"icons": patch
---

fix(icons): retry wasm-vips init on transient "could not allocate memory" failures

wasm-vips is a pthreads build, so its `WebAssembly.Memory` is `shared` with
`initial === maximum` and V8 commits the full 1 GiB region up front (a shared
backing store cannot grow once handed to worker threads). That size is baked into
the wasm binary and cannot be lowered at runtime. When electron-builder spawns
many `icon-tool.js` processes concurrently (its test suite fans icon conversions
out in parallel), each one tries to commit its own gigabyte and memory-constrained
CI runners — Windows in particular — refuse the allocation with
`WebAssembly.Memory(): could not allocate memory`.

The failures are transient: each conversion is short-lived, so a process that
briefly backs off gets its memory once peers finish and decommit. Vips
initialization now retries on memory-allocation errors with exponential backoff
and full jitter (to decorrelate concurrent processes' retries). Non-allocation
errors propagate immediately so real bugs are never masked.
