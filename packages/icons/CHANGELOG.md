# icons

## 1.2.3

### Patch Changes

- [#220](https://github.com/electron-userland/electron-builder-binaries/pull/220) [`40acc0b`](https://github.com/electron-userland/electron-builder-binaries/commit/40acc0b8ad6886b99d9878fd00ff475cce2ee4e3) Thanks [@mmaietta](https://github.com/mmaietta)! - fix(icons): store the 16px/32px macOS icons as ic04/ic05 ARGB so they no longer render corrupt in Finder

  Fixes electron-builder#9980, where the small app-icon sizes appeared corrupt in macOS
  Finder/Activity Monitor/Trash list views. The ICNS writer emitted the 16px/32px (and a
  spurious 64px) 1× icons as PNG inside the icp4/icp5/icp6 chunks. macOS does not render PNG
  data stored in those chunks correctly, so the small icons were garbled.

  The 16px and 32px 1× icons are now written as ic04/ic05 in ARGB form — exactly what Apple's
  own `iconutil` emits — and the bogus icp6 entry is gone. The generated ic04/ic05 chunks are
  byte-identical to iconutil's own output and were verified to render correctly through AppKit
  (CoreGraphics). Larger sizes remain PNG (ic07–ic14), and all standard iconset sizes are still
  present, so this keeps the small-icon coverage from [#9940](https://github.com/electron-userland/electron-builder-binaries/issues/9940) while fixing the corruption.

  - New `argb.ts`: ICNS ARGB encoder ('ARGB' magic + ICNS run-length-compressed A,R,G,B planes,
    straight/non-premultiplied — the convention macOS composites with).
  - `vips.ts`: factored the resize core into `resizeSquare`; added `resizeToRawRgba` for the raw
    RGBA pixels the ARGB encoder needs.
  - e2e: the iconutil check now also asserts the corrupt `icon_48x48.png` (icp6) is absent, and a
    new pixel-parity test decodes the ic04/ic05 ARGB chunks and asserts they match both the wasm
    pixels and iconutil's own ARGB encoding. (The comparison reads the ARGB chunks directly because
    `iconutil --convert iconset` is itself lossy for ARGB and is not a valid pixel oracle.)

## 1.2.2

### Patch Changes

- [#216](https://github.com/electron-userland/electron-builder-binaries/pull/216) [`3869267`](https://github.com/electron-userland/electron-builder-binaries/commit/386926742b532bfb79845d8e06034f97a480e5cc) Thanks [@mmaietta](https://github.com/mmaietta)! - chore(test): add `iconutil` to e2e test suite and migrate to macos GH runner

## 1.2.1

### Patch Changes

- [#214](https://github.com/electron-userland/electron-builder-binaries/pull/214) [`897a48e`](https://github.com/electron-userland/electron-builder-binaries/commit/897a48e5590bf7c8619346dada8a7ee4fd71d450) Thanks [@mmaietta](https://github.com/mmaietta)! - fix(icons): read all ICNS frame types, fix resampling quality, and add diagnostics

  Fixes electron-builder#9876, where a valid single-layer .icns used as an icon
  source failed with "Could not extract a PNG frame from ICNS file".

  - **ICNS input ([#9876](https://github.com/electron-userland/electron-builder-binaries/issues/9876)):** the extractor previously inspected only 5 hard-coded
    OSTypes (`ic08/ic09/ic10/ic13/ic14`). It now scans every parsed frame and
    returns the largest PNG, so a .icns whose only/largest PNG lives in any type
    (`icp4/icp5/icp6/ic07/ic11/ic12/…`) is read correctly. This also fixes a
    round-trip bug where the tool could not read the .icns files its own writer
    produced from small sources. ICNS magic and per-entry bounds are now validated.
  - **Diagnostics:** on extraction failure the CLI now lists the frames found and
    their detected encodings (png/jp2/argb/raw), and the tool emits optional debug
    logging via the standard `DEBUG=icons` convention (no new
    runtime dependency). JPEG2000/ARGB/legacy-raw frames remain undecodable by the
    bundled wasm-vips build but now produce an actionable message instead of a
    generic one.
  - **Resampling quality:** `ico` and Linux `set` no longer upscale sources beyond
    their native size, and all converters now preserve aspect ratio (non-square
    sources are padded to a transparent square instead of being stretched). Square
    sources are unchanged.
  - **ICNS output:** corrected `ic13` (256px) and `ic14` (512px) frame sizes to
    match the Apple spec (were 512/1024), and `createIcns` now validates that its
    input is a real PNG.
  - **wasm-vips:** `getVips()` memoizes the in-flight init promise so concurrent
    conversions share a single 1 GiB allocation instead of each spawning their own;
    the OOM-retry matcher recognizes more allocation-failure phrasings.

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
