// Binary format validators for ICNS, ICO, and PNG files.
// All functions throw on invalid input, return parsed metadata on success.

const PNG_SIGNATURE = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])

export function parsePngDimensions(buf: Buffer): { width: number; height: number } {
  if (!buf.slice(0, 8).equals(PNG_SIGNATURE)) throw new Error('Not a valid PNG file (bad signature)')
  if (buf.toString('ascii', 12, 16) !== 'IHDR') throw new Error('Missing IHDR chunk')
  return {
    width: buf.readUInt32BE(16),
    height: buf.readUInt32BE(20),
  }
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
