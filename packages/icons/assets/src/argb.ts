// ICNS ARGB encoder for the ic04 (16px) and ic05 (32px) OSTypes. macOS stores the small
// 1× icons as ARGB, NOT PNG: although the icp4/icp5/icp6 chunks can technically carry a PNG,
// macOS does not render those correctly and the small icons appeared corrupt in Finder's
// list/column/Trash views (electron-userland/electron-builder#9980).
//
// The payload is the literal magic 'ARGB' followed by the four 8-bit channels in A, R, G, B
// order, each run-length compressed with the ICNS PackBits variant (the same scheme used by
// the legacy is32/il32 types). RGB is stored straight (non-premultiplied): macOS composites
// the icon with straight alpha (verified by rendering an .icns through AppKit), which also
// matches what Apple's own `iconutil` writes. The byte layout was verified against macOS
// `iconutil` output.

// ICNS PackBits: a control byte ≥ 0x80 introduces a run of (control − 125) copies — i.e.
// 3…130 — of the following byte; a control byte < 0x80 introduces a literal run of
// (control + 1) — i.e. 1…128 — raw bytes. A run must be ≥ 3 identical bytes (a 2-byte run is
// not representable, so such bytes are emitted as a literal).
function packBits(data: Buffer): Buffer {
  const out: number[] = []
  const n = data.length
  let i = 0
  while (i < n) {
    let run = 1
    while (i + run < n && data[i + run] === data[i] && run < 130) run++
    if (run >= 3) {
      out.push(0x80 | (run - 3), data[i])
      i += run
      continue
    }
    // Collect a literal block, stopping before the next run of ≥ 3 and at the 128-byte cap.
    const literal: number[] = []
    while (i < n && literal.length < 128) {
      let ahead = 1
      while (i + ahead < n && data[i + ahead] === data[i] && ahead < 3) ahead++
      if (ahead >= 3) break
      literal.push(data[i])
      i++
    }
    out.push(literal.length - 1, ...literal)
  }
  return Buffer.from(out)
}

// Encode straight row-major RGBA pixels (size*size*4 bytes) into an ICNS ARGB payload.
export function encodeArgb(rgba: Buffer, size: number): Buffer {
  const pixels = size * size
  if (rgba.length !== pixels * 4) {
    throw new Error(`encodeArgb: expected ${pixels * 4} RGBA bytes for ${size}px, got ${rgba.length}`)
  }
  const a = Buffer.allocUnsafe(pixels)
  const r = Buffer.allocUnsafe(pixels)
  const g = Buffer.allocUnsafe(pixels)
  const b = Buffer.allocUnsafe(pixels)
  for (let i = 0; i < pixels; i++) {
    r[i] = rgba[i * 4]
    g[i] = rgba[i * 4 + 1]
    b[i] = rgba[i * 4 + 2]
    a[i] = rgba[i * 4 + 3]
  }
  return Buffer.concat([Buffer.from('ARGB', 'ascii'), packBits(a), packBits(r), packBits(g), packBits(b)])
}
