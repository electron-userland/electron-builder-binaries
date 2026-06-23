---
"icons": patch
---

fix(icons): store the 16px/32px macOS icons as ic04/ic05 ARGB so they no longer render corrupt in Finder

Fixes electron-builder#9980, where the small app-icon sizes appeared corrupt in macOS
Finder/Activity Monitor/Trash list views. The ICNS writer emitted the 16px/32px (and a
spurious 64px) 1× icons as PNG inside the icp4/icp5/icp6 chunks. macOS does not render PNG
data stored in those chunks correctly, so the small icons were garbled.

The 16px and 32px 1× icons are now written as ic04/ic05 in ARGB form — exactly what Apple's
own `iconutil` emits — and the bogus icp6 entry is gone. The generated ic04/ic05 chunks are
byte-identical to iconutil's own output and were verified to render correctly through AppKit
(CoreGraphics). Larger sizes remain PNG (ic07–ic14), and all standard iconset sizes are still
present, so this keeps the small-icon coverage from #9940 while fixing the corruption.

- New `argb.ts`: ICNS ARGB encoder ('ARGB' magic + ICNS run-length-compressed A,R,G,B planes,
  straight/non-premultiplied — the convention macOS composites with).
- `vips.ts`: factored the resize core into `resizeSquare`; added `resizeToRawRgba` for the raw
  RGBA pixels the ARGB encoder needs.
- e2e: the iconutil check now also asserts the corrupt `icon_48x48.png` (icp6) is absent, and a
  new pixel-parity test decodes the ic04/ic05 ARGB chunks and asserts they match both the wasm
  pixels and iconutil's own ARGB encoding. (The comparison reads the ARGB chunks directly because
  `iconutil --convert iconset` is itself lossy for ARGB and is not a valid pixel oracle.)
