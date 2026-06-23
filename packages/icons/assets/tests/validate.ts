// Binary format validators for ICNS, ICO, and PNG files.
// All functions throw on invalid input, return parsed metadata on success.

import { inflateSync } from 'zlib'

const PNG_SIGNATURE = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])

export function parsePngDimensions(buf: Buffer): { width: number; height: number } {
  if (!buf.slice(0, 8).equals(PNG_SIGNATURE)) throw new Error('Not a valid PNG file (bad signature)')
  if (buf.toString('ascii', 12, 16) !== 'IHDR') throw new Error('Missing IHDR chunk')
  return {
    width: buf.readUInt32BE(16),
    height: buf.readUInt32BE(20),
  }
}

// Minimal PNG decoder (8-bit, non-interlaced, color types 0/2/4/6) → straight RGBA bytes.
// Enough to read the PNGs that `iconutil` and wasm-vips emit so tests can compare pixels.
export function decodePngToRgba(buf: Buffer): { width: number; height: number; rgba: Buffer } {
  const { width, height } = parsePngDimensions(buf)
  const depth = buf[24]
  const colorType = buf[25]
  const interlace = buf[28]
  if (depth !== 8) throw new Error(`decodePngToRgba: only 8-bit depth supported (got ${depth})`)
  if (interlace !== 0) throw new Error('decodePngToRgba: interlaced PNG not supported')
  const channels = colorType === 6 ? 4 : colorType === 2 ? 3 : colorType === 4 ? 2 : colorType === 0 ? 1 : 0
  if (channels === 0) throw new Error(`decodePngToRgba: unsupported color type ${colorType}`)

  const idat: Buffer[] = []
  let off = 8
  while (off + 8 <= buf.length) {
    const len = buf.readUInt32BE(off)
    const type = buf.toString('ascii', off + 4, off + 8)
    if (type === 'IDAT') idat.push(buf.subarray(off + 8, off + 8 + len))
    if (type === 'IEND') break
    off += 12 + len
  }
  const raw = inflateSync(Buffer.concat(idat))

  const stride = width * channels
  const cur = Buffer.alloc(stride)
  const prev = Buffer.alloc(stride)
  const out = Buffer.alloc(width * height * 4)
  let p = 0
  for (let y = 0; y < height; y++) {
    const filter = raw[p++]
    for (let x = 0; x < stride; x++) {
      const rawByte = raw[p++]
      const a = x >= channels ? cur[x - channels] : 0
      const b = prev[x]
      const c = x >= channels ? prev[x - channels] : 0
      let v: number
      switch (filter) {
        case 0: v = rawByte; break
        case 1: v = rawByte + a; break
        case 2: v = rawByte + b; break
        case 3: v = rawByte + ((a + b) >> 1); break
        case 4: {
          const pa = Math.abs(b - c)
          const pb = Math.abs(a - c)
          const pc = Math.abs(a + b - 2 * c)
          const pred = pa <= pb && pa <= pc ? a : pb <= pc ? b : c
          v = rawByte + pred
          break
        }
        default: throw new Error(`decodePngToRgba: unsupported filter ${filter}`)
      }
      cur[x] = v & 0xff
    }
    for (let x = 0; x < width; x++) {
      const o = (y * width + x) * 4
      if (channels === 4) {
        out[o] = cur[x * 4]; out[o + 1] = cur[x * 4 + 1]; out[o + 2] = cur[x * 4 + 2]; out[o + 3] = cur[x * 4 + 3]
      } else if (channels === 3) {
        out[o] = cur[x * 3]; out[o + 1] = cur[x * 3 + 1]; out[o + 2] = cur[x * 3 + 2]; out[o + 3] = 255
      } else if (channels === 2) {
        out[o] = out[o + 1] = out[o + 2] = cur[x * 2]; out[o + 3] = cur[x * 2 + 1]
      } else {
        out[o] = out[o + 1] = out[o + 2] = cur[x]; out[o + 3] = 255
      }
    }
    cur.copy(prev)
  }
  return { width, height, rgba: out }
}

// Returns the list of OSType entry IDs found in the ICNS file (e.g. ['ic07', 'ic08', ...])
export function parseIcns(buf: Buffer): string[] {
  if (buf.toString('ascii', 0, 4) !== 'icns') throw new Error('Not a valid ICNS file (bad magic)')
  const fileSize = buf.readUInt32BE(4)
  const types: string[] = []
  let offset = 8
  while (offset + 8 <= Math.min(fileSize, buf.length)) {
    const type = buf.toString('ascii', offset, offset + 4)
    const chunkSize = buf.readUInt32BE(offset + 4)
    if (chunkSize < 8) throw new Error(`Invalid ICNS chunk size ${chunkSize} at offset ${offset}`)
    types.push(type)
    offset += chunkSize
  }
  return types
}

// Returns the raw payload (without the 8-byte type/length header) of the first ICNS entry
// matching `ostype`, or null if absent.
export function extractIcnsChunk(icns: Buffer, ostype: string): Buffer | null {
  let off = 8
  while (off + 8 <= icns.length) {
    const type = icns.toString('ascii', off, off + 4)
    const len = icns.readUInt32BE(off + 4)
    if (len < 8) break
    if (type === ostype) return icns.subarray(off + 8, off + len)
    off += len
  }
  return null
}

// Decode an ICNS ARGB payload (the ic04/ic05 format: literal 'ARGB' + the four channels
// A, R, G, B, each ICNS-RLE compressed) into straight row-major RGBA bytes.
export function decodeArgb(payload: Buffer, size: number): Buffer {
  if (payload.toString('ascii', 0, 4) !== 'ARGB') throw new Error('decodeArgb: missing ARGB magic')
  const pixels = size * size
  let body = payload.subarray(4)
  const planes: Buffer[] = []
  for (let ch = 0; ch < 4; ch++) {
    const out = Buffer.alloc(pixels)
    let o = 0
    let i = 0
    while (o < pixels && i < body.length) {
      const control = body[i++]
      if (control & 0x80) {
        const run = control - 125
        const v = body[i++]
        for (let k = 0; k < run && o < pixels; k++) out[o++] = v
      } else {
        const lit = control + 1
        for (let k = 0; k < lit && i < body.length && o < pixels; k++) out[o++] = body[i++]
      }
    }
    planes.push(out)
    body = body.subarray(i)
  }
  const [a, r, g, b] = planes
  const rgba = Buffer.alloc(pixels * 4)
  for (let i = 0; i < pixels; i++) {
    rgba[i * 4] = r[i]
    rgba[i * 4 + 1] = g[i]
    rgba[i * 4 + 2] = b[i]
    rgba[i * 4 + 3] = a[i]
  }
  return rgba
}

// Returns the list of image widths found in the ICO file (0 in the header means 256)
export function parseIco(buf: Buffer): number[] {
  if (buf.readUInt16LE(0) !== 0) throw new Error('Not a valid ICO file (reserved field non-zero)')
  if (buf.readUInt16LE(2) !== 1) throw new Error('Not a valid ICO file (type field must be 1)')
  const count = buf.readUInt16LE(4)
  if (count === 0) throw new Error('ICO file contains no images')
  const sizes: number[] = []
  for (let i = 0; i < count; i++) {
    const offset = 6 + i * 16
    const w = buf.readUInt8(offset) || 256  // 0 encodes 256
    sizes.push(w)
  }
  return sizes
}
