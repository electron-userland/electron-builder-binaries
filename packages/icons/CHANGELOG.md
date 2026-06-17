# icons

## 1.2.0

### Minor Changes

- [#212](https://github.com/electron-userland/electron-builder-binaries/pull/212) [`5df4dc1`](https://github.com/electron-userland/electron-builder-binaries/commit/5df4dc1838ff7916697af2c1e7a6997ae67ab681) Thanks [@mmaietta](https://github.com/mmaietta)! - feat(icons): icon-tool CLI accepts space-delimited arguments

  The CLI now parses both the space-delimited `--key value` form and the original
  concatenated `--key=value` form, so callers no longer have to build
  `--input=<path>` strings. Parsing is backward compatible — existing `--key=value`
  invocations continue to work unchanged. Values may contain spaces or `=`
  characters when passed as separate argv tokens.

### Patch Changes

- [#212](https://github.com/electron-userland/electron-builder-binaries/pull/212) [`5df4dc1`](https://github.com/electron-userland/electron-builder-binaries/commit/5df4dc1838ff7916697af2c1e7a6997ae67ab681) Thanks [@mmaietta](https://github.com/mmaietta)! - fix(icons): retry wasm-vips init on transient "could not allocate memory" failures

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

## 1.1.0

### Minor Changes

- [#204](https://github.com/electron-userland/electron-builder-binaries/pull/204) [`b96a825`](https://github.com/electron-userland/electron-builder-binaries/commit/b96a825027325023d955f96a3f1d8eb9b5ea112e) Thanks [@mmaietta](https://github.com/mmaietta)! - fix(icons): replace png2icons with wasm-vips Lanczos3 resampling for high-quality icon conversion

## 1.0.1

### Patch Changes

- [#186](https://github.com/electron-userland/electron-builder-binaries/pull/186) [`a568ac2`](https://github.com/electron-userland/electron-builder-binaries/commit/a568ac27c711b40be9b0f77222add8ef8e7cdf65) Thanks [@mmaietta](https://github.com/mmaietta)! - chore(deploy): redeploying due to failed attest CJS->ESM module update

## 1.0.0

### Major Changes

- [#183](https://github.com/electron-userland/electron-builder-binaries/pull/183) [`db378ba`](https://github.com/electron-userland/electron-builder-binaries/commit/db378baff88005fc74462b224c9a3c27e3606771) Thanks [@mmaietta](https://github.com/mmaietta)! - feat(icons): new `packages/icons` portable icon conversion toolset that accepts `.png`, `.svg`, `.icns` and can output `icns` (macOS), `ico` (Windows), `set` (Linux PNG set at 16/24/32/48/64/128/256/512 px)
