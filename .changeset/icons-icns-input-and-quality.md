---
"icons": patch
---

fix(icons): read all ICNS frame types, fix resampling quality, and add diagnostics

Fixes electron-builder#9876, where a valid single-layer .icns used as an icon
source failed with "Could not extract a PNG frame from ICNS file".

- **ICNS input (#9876):** the extractor previously inspected only 5 hard-coded
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
