const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])

export function isPng(data: Buffer): boolean {
  return data.length >= 8 && data.subarray(0, 8).equals(PNG_SIGNATURE)
}

// Read width/height from a PNG's IHDR chunk (bytes 16-23). Throws if the buffer
// is not a structurally valid PNG so callers never silently mis-size a non-PNG
// input (the IHDR offset is only meaningful for real PNGs).
export function readPngSize(data: Buffer): { width: number; height: number } {
  if (data.length < 24 || !isPng(data) || data.toString('ascii', 12, 16) !== 'IHDR') {
    throw new Error('Input is not a valid PNG (missing signature or IHDR chunk)')
  }
  return { width: data.readUInt32BE(16), height: data.readUInt32BE(20) }
}
